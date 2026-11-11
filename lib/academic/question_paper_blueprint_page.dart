import 'package:flutter/material.dart';

class QuestionPaperBlueprintPage extends StatelessWidget {
  const QuestionPaperBlueprintPage({super.key});

  static const _steps = [
    (
      '1',
      'Paper setup',
      'Class, subject, examination, duration, total marks, and instructions.',
    ),
    (
      '2',
      'Paper sections',
      'Add sections and define their order, marks, and attempt rules.',
    ),
    (
      '3',
      'Question criteria',
      'Choose question formats, chapter or topic, learning outcome, and difficulty.',
    ),
    (
      '4',
      'Mark distribution',
      'Check each question and section against the paper total.',
    ),
    (
      '5',
      'Preview and print',
      'Review a school-branded paper layout before producing the final copy.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(title: const Text('Question Paper Maker Blueprint')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.edit_document,
                  size: 34,
                  color: Color(0xFFC62828),
                ),
                const SizedBox(height: 12),
                Text(
                  'Planned paper workflow',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'This page is the working blueprint. Detailed paper rules, question types, editing controls, and the final printed design will be added after the school confirms its criteria.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final step in _steps)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
                child: Text(step.$1),
              ),
              title: Text(step.$2),
              subtitle: Text(step.$3),
            ),
          ),
        const SizedBox(height: 10),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No examination papers are generated from this blueprint yet.',
            ),
          ),
        ),
      ],
    ),
  );
}
