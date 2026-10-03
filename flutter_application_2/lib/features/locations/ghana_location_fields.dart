import 'package:flutter/material.dart';

import 'ghana_location_service.dart';

class GhanaLocationFields extends StatefulWidget {
  const GhanaLocationFields({required this.regionController, required this.districtController, required this.townController, this.onChanged, super.key});

  final TextEditingController regionController;
  final TextEditingController districtController;
  final TextEditingController townController;
  final VoidCallback? onChanged;

  @override
  State<GhanaLocationFields> createState() => _GhanaLocationFieldsState();
}

class _GhanaLocationFieldsState extends State<GhanaLocationFields> {
  final _service = GhanaLocationService();
  late Future<GhanaLocationCatalog> _catalog;
  String? _error;

  @override
  void initState() {
    super.initState();
    _catalog = _service.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GhanaLocationCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        if (snapshot.hasError) return Text('Ghana locations unavailable. You can enter the saved values manually.', style: TextStyle(color: Theme.of(context).colorScheme.error));
        final catalog = snapshot.data!;
        final districts = catalog.districtsFor(widget.regionController.text.trim());
        final towns = catalog.townsFor(widget.districtController.text.trim());
        return Column(children: [
          _searchableField(context, label: 'Region *', controller: widget.regionController, values: catalog.regions, onSelected: (value) {
            widget.regionController.text = value;
            if (!districts.contains(widget.districtController.text)) widget.districtController.clear();
            widget.townController.clear();
            _changed();
          }),
          const SizedBox(height: 16),
          _searchableField(context, label: 'District *', controller: widget.districtController, values: districts, onSelected: (value) {
            widget.districtController.text = value;
            widget.townController.clear();
            _changed();
          }, allowManual: districts.isEmpty),
          const SizedBox(height: 16),
          _searchableField(context, label: 'Town *', controller: widget.townController, values: towns, onSelected: (value) {
            widget.townController.text = value;
            _changed();
          }, allowManual: towns.isEmpty),
          if (_error != null) Align(alignment: Alignment.centerLeft, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]);
      },
    );
  }

  Widget _searchableField(BuildContext context, {required String label, required TextEditingController controller, required List<String> values, required ValueChanged<String> onSelected, bool allowManual = false}) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (value) => value.text.trim().isEmpty ? values : values.where((item) => item.toLowerCase().contains(value.text.toLowerCase())),
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, focusNode, submit) {
        textController.text = controller.text;
        return TextFormField(controller: textController, focusNode: focusNode, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.location_on_outlined)), onChanged: (value) { controller.text = value; _changed(); }, validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null);
      },
      optionsViewBuilder: (context, onSelected, options) => Align(alignment: Alignment.topLeft, child: Material(elevation: 4, child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 220, maxWidth: 500), child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: options.map((option) => ListTile(title: Text(option), onTap: () => onSelected(option))).toList())))),
    );
  }

  void _changed() {
    setState(() {});
    widget.onChanged?.call();
  }
}
