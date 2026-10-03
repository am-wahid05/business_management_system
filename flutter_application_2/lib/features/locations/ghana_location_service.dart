import 'dart:convert';

import 'package:http/http.dart' as http;

class GhanaLocation {
  const GhanaLocation({required this.region, this.district, this.town});

  final String region;
  final String? district;
  final String? town;
}

class GhanaLocationCatalog {
  const GhanaLocationCatalog({required this.regions, required this.districtsByRegion, required this.townsByDistrict, this.fromApi = false});

  final List<String> regions;
  final Map<String, List<String>> districtsByRegion;
  final Map<String, List<String>> townsByDistrict;
  final bool fromApi;

  List<String> districtsFor(String? region) => districtsByRegion[region] ?? const [];
  List<String> townsFor(String? district) => townsByDistrict[district] ?? const [];

  bool isValid(GhanaLocation location) {
    final districts = districtsFor(location.region);
    if (location.district != null && districts.isNotEmpty && !districts.contains(location.district)) return false;
    final towns = townsFor(location.district);
    if (location.town != null && towns.isNotEmpty && !towns.contains(location.town)) return false;
    return true;
  }
}

class GhanaLocationService {
  GhanaLocationService({http.Client? client, this.endpoint = 'https://countriesnow.space/api/v0.1/countries/states'}) : _client = client ?? http.Client();

  final http.Client _client;
  final String endpoint;
  GhanaLocationCatalog? _cache;

  static const regions = [
    'Ahafo',
    'Ashanti',
    'Bono',
    'Bono East',
    'Central',
    'Eastern',
    'Greater Accra',
    'North East',
    'Northern',
    'Oti',
    'Savannah',
    'Upper East',
    'Upper West',
    'Volta',
    'Western',
    'Western North',
  ];

  Future<GhanaLocationCatalog> load() async {
    if (_cache != null) return _cache!;
    try {
      final response = await _client.post(Uri.parse(endpoint), headers: {'content-type': 'application/json'}, body: jsonEncode({'country': 'Ghana'})).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw const FormatException('Ghana location service returned an error');
      final decoded = jsonDecode(response.body);
      final states = decoded is Map<String, dynamic> ? decoded['data'] : null;
      final apiRegions = states is List ? states.map((item) => item is Map ? item['name']?.toString() : null).whereType<String>().toList() : <String>[];
      final selected = apiRegions.isEmpty ? regions : apiRegions;
      return _cache = GhanaLocationCatalog(regions: List.unmodifiable(selected), districtsByRegion: const {}, townsByDistrict: const {}, fromApi: apiRegions.isNotEmpty);
    } catch (_) {
      return _cache = const GhanaLocationCatalog(regions: regions, districtsByRegion: {}, townsByDistrict: {}, fromApi: false);
    }
  }
}
