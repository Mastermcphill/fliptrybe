import 'package:flutter/material.dart';

class ProjectionTable extends StatelessWidget {
  const ProjectionTable({
    super.key,
    required this.rows,
    required this.money,
  });

  final List<Map<String, double>> rows;
  final String Function(num value) money;

  String _label(double? index) {
    final i = (index ?? 0).toInt();
    switch (i) {
      case 0:
        return 'Daily';
      case 1:
        return 'Weekly';
      case 2:
        return 'Monthly';
      default:
        return 'Yearly';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Earnings Projection Table',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: const Color(0xFFCFD8DC)),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Period',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Gross',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Commission',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Net',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Take-home',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                ...rows.map((row) {
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(_label(row['labelIndex'])),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['gross'] ?? 0)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['commission'] ?? 0)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['net'] ?? 0)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['takeHome'] ?? 0)),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
