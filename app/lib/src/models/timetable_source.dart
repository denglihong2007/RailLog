enum TimetableSource {
  online('在线（包含2025及以后）'),
  year2009('2009'),
  year2010('2010'),
  year2011('2011'),
  year2012('2012'),
  year2013('2013'),
  year2014('2014'),
  year2015('2015'),
  year2016('2016'),
  year2017('2017'),
  year2018('2018'),
  year2019('2019'),
  year2020('2020'),
  year2021('2021'),
  year2022('2022'),
  year2023('2023'),
  year2024('2024');

  const TimetableSource(this.label);

  final String label;

  int? get year => switch (this) {
    online => null,
    year2009 => 2009,
    year2010 => 2010,
    year2011 => 2011,
    year2012 => 2012,
    year2013 => 2013,
    year2014 => 2014,
    year2015 => 2015,
    year2016 => 2016,
    year2017 => 2017,
    year2018 => 2018,
    year2019 => 2019,
    year2020 => 2020,
    year2021 => 2021,
    year2022 => 2022,
    year2023 => 2023,
    year2024 => 2024,
  };

  bool get isOnline => this == TimetableSource.online;

  static TimetableSource forYear(int year) {
    return switch (year) {
      2009 => year2009,
      2010 => year2010,
      2011 => year2011,
      2012 => year2012,
      2013 => year2013,
      2014 => year2014,
      2015 => year2015,
      2016 => year2016,
      2017 => year2017,
      2018 => year2018,
      2019 => year2019,
      2020 => year2020,
      2021 => year2021,
      2022 => year2022,
      2023 => year2023,
      2024 => year2024,
      _ => online,
    };
  }
}
