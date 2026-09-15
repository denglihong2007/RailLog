param(
    [string]$OutputPath = '',

    [ValidateRange(1, 100)]
    [int]$MinimumWordLength = 1,

    [string]$WordsDirectory = '',

    [switch]$ActiveTripsOnly
)

$ErrorActionPreference = 'Stop'

$sqliteCommand = Get-Command sqlite3 -ErrorAction SilentlyContinue
if (-not $sqliteCommand) {
    throw '未找到 sqlite3，请先安装并加入 PATH。'
}
$sqlite = $sqliteCommand.Source

$database = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\api\raillog.db')).Path
$project = Join-Path $PSScriptRoot '..\api\RailLog.API.csproj'
if ([string]::IsNullOrWhiteSpace($WordsDirectory)) {
    $secretMatch = dotnet user-secrets list --project $project |
        Select-String -Pattern '^ContentModeration:SensitiveWordsDirectory\s*=\s*(.+)$'
    if (-not $secretMatch) {
        throw '未找到 ContentModeration:SensitiveWordsDirectory 配置。'
    }

    $WordsDirectory = $secretMatch.Matches[0].Groups[1].Value.Trim()
}
$wordsDirectory = [IO.Path]::GetFullPath($WordsDirectory)
if (-not (Test-Path -LiteralPath $wordsDirectory -PathType Container)) {
    throw "敏感词目录不存在：$wordsDirectory"
}

$wordFiles = @(
    Get-ChildItem -LiteralPath $wordsDirectory -File -Recurse |
        Where-Object { $_.Extension -ieq '.txt' } |
        Sort-Object FullName)
if ($wordFiles.Count -eq 0) {
    throw "敏感词目录中没有 .txt 文件：$wordsDirectory"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([IO.Path]::GetTempPath()) `
        "raillog-sensitive-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$utf8 = [Text.UTF8Encoding]::new($false)
$previousOutputEncoding = [Console]::OutputEncoding

$matcherSource = @'
using System;
using System.Collections.Generic;

namespace RailLogTools
{
    public sealed class SensitiveWordMatcher
    {
        private sealed class Node
        {
            public Dictionary<char, int> Children { get; } =
                new Dictionary<char, int>();

            public List<string> Outputs { get; } =
                new List<string>();

            public int Failure { get; set; }
        }

        private readonly List<Node> _nodes = new List<Node>();

        public SensitiveWordMatcher(IEnumerable<string> words)
        {
            _nodes.Add(new Node());
            foreach (string word in words)
            {
                int state = 0;
                foreach (char character in word)
                {
                    if (!_nodes[state].Children.TryGetValue(character, out int next))
                    {
                        next = _nodes.Count;
                        _nodes[state].Children[character] = next;
                        _nodes.Add(new Node());
                    }

                    state = next;
                }

                _nodes[state].Outputs.Add(word);
            }

            BuildFailureLinks();
        }

        public string[] FindAll(string text)
        {
            var matches = new HashSet<string>(StringComparer.Ordinal);
            int state = 0;

            foreach (char character in text)
            {
                while (state != 0 &&
                    !_nodes[state].Children.TryGetValue(character, out _))
                {
                    state = _nodes[state].Failure;
                }

                if (_nodes[state].Children.TryGetValue(character, out int next))
                {
                    state = next;
                }

                foreach (string output in _nodes[state].Outputs)
                {
                    matches.Add(output);
                }
            }

            return new List<string>(matches).ToArray();
        }

        private void BuildFailureLinks()
        {
            var queue = new Queue<int>();
            foreach (int child in _nodes[0].Children.Values)
            {
                _nodes[child].Failure = 0;
                queue.Enqueue(child);
            }

            while (queue.Count > 0)
            {
                int current = queue.Dequeue();
                foreach (KeyValuePair<char, int> entry in _nodes[current].Children)
                {
                    char character = entry.Key;
                    int child = entry.Value;
                    int failure = _nodes[current].Failure;

                    while (failure != 0 &&
                        !_nodes[failure].Children.TryGetValue(character, out _))
                    {
                        failure = _nodes[failure].Failure;
                    }

                    if (_nodes[failure].Children.TryGetValue(character, out int target) &&
                        target != child)
                    {
                        _nodes[child].Failure = target;
                    }
                    else
                    {
                        _nodes[child].Failure = 0;
                    }

                    _nodes[child].Outputs.AddRange(
                        _nodes[_nodes[child].Failure].Outputs);
                    queue.Enqueue(child);
                }
            }
        }
    }
}
'@

if (-not ('RailLogTools.SensitiveWordMatcher' -as [type])) {
    Add-Type -TypeDefinition $matcherSource -Language CSharp
}

function Normalize-Text([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ''
    }

    $normalized = $value.Normalize([Text.NormalizationForm]::FormKC)
    $builder = [Text.StringBuilder]::new($normalized.Length)
    foreach ($character in $normalized.ToCharArray()) {
        $code = [int]$character
        if (-not [char]::IsWhiteSpace($character) -and
            $code -notin @(0x200B, 0x200C, 0x200D, 0xFEFF)) {
            [void]$builder.Append($character)
        }
    }

    return $builder.ToString().ToLowerInvariant()
}

function Read-SqliteRows([string]$query) {
    $json = ((& $sqlite -readonly -json $database $query) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        return @()
    }

    return @($json | ConvertFrom-Json)
}

try {
    [Console]::OutputEncoding = $utf8

    $words = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    $wordDisplayByNormalized = [Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::Ordinal)
    foreach ($wordFile in $wordFiles) {
        foreach ($line in [IO.File]::ReadLines($wordFile.FullName)) {
            $displayWord = $line.Trim()
            $word = Normalize-Text $line
            if ($word.Length -ge $MinimumWordLength -and $words.Add($word)) {
                $wordDisplayByNormalized[$word] = $displayWord
            }
        }
    }
    $matcher = [RailLogTools.SensitiveWordMatcher]::new($words)

    $records = [Collections.Generic.List[object]]::new()

    function Add-Record(
        [string]$field,
        [string]$recordId,
        [string]$userId,
        [bool]$deleted,
        [string]$content) {
        $normalized = Normalize-Text $content
        if ($normalized.Length -eq 0) {
            return
        }

        $records.Add([pscustomobject]@{
            Field = $field
            RecordId = $recordId
            UserId = $userId
            Deleted = $deleted
            Content = $content
            Normalized = $normalized
        })
    }

    $users = Read-SqliteRows 'SELECT Id, DisplayName, Bio FROM AspNetUsers;'
    foreach ($row in $users) {
        Add-Record 'Users.DisplayName' ([string]$row.Id) ([string]$row.Id) $false ([string]$row.DisplayName)
        if (-not [string]::IsNullOrWhiteSpace([string]$row.Bio)) {
            Add-Record 'Users.Bio' ([string]$row.Id) ([string]$row.Id) $false ([string]$row.Bio)
        }
    }

    $reviews = Read-SqliteRows 'SELECT Id, UserId, Comment FROM EntityReviews;'
    foreach ($row in $reviews) {
        Add-Record 'EntityReviews.Comment' ([string]$row.Id) ([string]$row.UserId) $false ([string]$row.Comment)
    }

    $tripWhere = if ($ActiveTripsOnly) {
        "WHERE Notes IS NOT NULL AND trim(Notes) <> '' AND DeletedAt IS NULL"
    }
    else {
        "WHERE Notes IS NOT NULL AND trim(Notes) <> ''"
    }
    $trips = Read-SqliteRows `
        "SELECT Id, UserId, Notes, DeletedAt FROM TripRecords $tripWhere;"
    foreach ($row in $trips) {
        $deleted = $null -ne $row.DeletedAt -and
            -not [string]::IsNullOrWhiteSpace([string]$row.DeletedAt)
        Add-Record 'TripRecords.Notes' ([string]$row.Id) ([string]$row.UserId) $deleted ([string]$row.Notes)
    }

    $results = [Collections.Generic.List[object]]::new()
    $matchingRecordCount = 0
    foreach ($record in $records) {
        $matchedWords = @($matcher.FindAll($record.Normalized) | Sort-Object)
        if ($matchedWords.Count -eq 0) {
            continue
        }

        $matchingRecordCount++
        foreach ($word in $matchedWords) {
            $results.Add([pscustomobject]@{
                Field = $record.Field
                RecordId = $record.RecordId
                UserId = $record.UserId
                Deleted = $record.Deleted
                SensitiveWord = $wordDisplayByNormalized[$word]
                Content = $record.Content
            })
        }
    }

    $extension = [IO.Path]::GetExtension($OutputPath).ToLowerInvariant()
    if ($extension -eq '.json') {
        $json = if ($results.Count -eq 0) {
            '[]'
        }
        else {
            $results | ConvertTo-Json -Depth 5
        }
        [IO.File]::WriteAllText($OutputPath, $json, $utf8)
    }
    else {
        $csv = if ($results.Count -eq 0) {
            'Field,RecordId,UserId,Deleted,SensitiveWord,Content'
        }
        else {
            $results |
                Select-Object Field, RecordId, UserId, Deleted, SensitiveWord, Content |
                ConvertTo-Csv -NoTypeInformation
        }
        [IO.File]::WriteAllLines($OutputPath, $csv, [Text.UTF8Encoding]::new($true))
    }

    Write-Output "扫描完成：$matchingRecordCount 条记录命中，$($results.Count) 个敏感词命中项。"
    Write-Output "敏感内容报告：$OutputPath"
    $results |
        Group-Object Field |
        Sort-Object Name |
        Select-Object Name, Count |
        Format-Table -AutoSize
}
finally {
    [Console]::OutputEncoding = $previousOutputEncoding
}
