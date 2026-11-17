/// Synthetic Study Bank / Start Here rows shaped like the PRD headers.
/// (The live headers are unverified: secrets were dummy at build time.)
List<Map<String, dynamic>> studyBankRows({int t1 = 6, int t2 = 2}) => [
  for (var i = 0; i < t1 + t2; i++)
    {
      '_row': i + 2,
      'Question ID': i < t1 ? 'D${i + 1}.1' : 'X${i + 1}',
      'Source tab': i.isEven ? 'Debasmita 100' : 'My work',
      'Topic': 'Topic $i',
      'Area': 'Senior',
      'Tier': i < t1 ? 'T1' : 'T2',
      'Type': 'Concept',
      'Stars': '',
      'Question': 'Question number $i?',
      'Follow-ups': 'Follow $i a; Follow $i b',
      'Answer points / rubric': 'Point A$i; Point B$i; Point C$i',
      'Project': '',
      'Related question': '',
      'Status': '',
    },
];

List<Map<String, dynamic>> startHereRows() => [
  {
    '_row': 2,
    'Current focus': 'Next action',
    'D1.1 · Platform channels deep dive': 'Open the method channel file',
  },
  {
    '_row': 3,
    'Current focus': 'Where to resume',
    'D1.1 · Platform channels deep dive': 'First session pending',
  },
];
