import 'package:flutter/material.dart';

class SuggestionDetailScreen extends StatelessWidget {
  final String suggestionId;
  const SuggestionDetailScreen({super.key, required this.suggestionId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: Center(
        child: Text('Detail for $suggestionId'),
      ),
    );
  }
}
