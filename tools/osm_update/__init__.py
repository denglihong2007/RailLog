"""RailLog 的 OSM 铁路底图管线：从整网 PBF 到 app/assets/db/rail_tracks.db。

目录里的东西一律「同目录平级 import」（`import build_rail_tracks`），每个脚本自己把所在
目录插进 sys.path，所以既能当脚本直接跑，也能被 unittest 当包发现：

    python tools/osm_update/update.py                 # 一键：下载 + 重建
    python tools/osm_update/build_rail_tracks.py ...  # 只重建
    cd tools && python -m unittest discover -p "test_*.py"

各文件的分工见 README.md。
"""
