import 'package:flutter/material.dart';

class MoneyboxProjectionTable extends StatelessWidget {
  const MoneyboxProjectionTable({
    super.key,
    required this.rows,
    required this.money,
  });

  final List<Map<String, double>> rows;
  final String Function(num value) money;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MoneyBox Projection by Tier',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: const Color(0xFFCFD8DC)),
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Tier',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Duration',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Locked principal',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Bonus',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Maturity total',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                ...rows.map((row) {
                  final tier = (row['tier'] ?? 0).toInt();
                  final days = (row['days'] ?? 0).toInt();
                  final bonusPct = (row['bonusPct'] ?? 0).toStringAsFixed(0);
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('Tier $tier'),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('$days days ($bonusPct%)'),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['principal'] ?? 0)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['bonus'] ?? 0)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(money(row['maturity'] ?? 0)),
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
