const String defaultDiscoveryCity = 'Lagos';
const String defaultDiscoveryState = 'Lagos';

const List<String> tier1Cities = <String>[
  'Lagos',
  'Abuja',
  'Port Harcourt',
  'Ibadan',
  'Kano',
  'Enugu',
  'Benin City',
  'Kaduna',
];

const List<String> tier2Cities = <String>[
  'Abeokuta',
  'Uyo',
  'Warri',
  'Asaba',
  'Ilorin',
  'Owerri',
  'Calabar',
  'Jos',
  'Akure',
  'Osogbo',
];

const List<String> tier3Cities = <String>[
  'Lokoja',
  'Minna',
  'Yola',
  'Gombe',
  'Bauchi',
  'Maiduguri',
  'Sokoto',
  'Katsina',
  'Ado-Ekiti',
  'Makurdi',
];

const List<String> nigeriaTieredCities = <String>[
  ...tier1Cities,
  ...tier2Cities,
  ...tier3Cities,
];
