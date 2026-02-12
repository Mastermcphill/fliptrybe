import 'package:flutter/material.dart';

class HowItWorksFeeTable extends StatelessWidget {
  const HowItWorksFeeTable({
    super.key,
    required this.headers,
    required this.rows,
  });

  final List<String> headers;
  final List<List<String>> rows;

  TableRow _headerRow() {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF0F2F5)),
      children: headers
          .map(
            (header) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                header,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          )
          .toList(),
    );
  }

  TableRow _valueRow(List<String> values) {
    return TableRow(
      children: values
          .map((value) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(value),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(color: const Color(0xFFCFD8DC)),
      children: [
        _headerRow(),
        ...rows.map(_valueRow),
      ],
    );
  }
}
