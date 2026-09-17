import 'package:flutter/material.dart';
import '../services/prediction_service.dart';

class RiskCard extends StatelessWidget {
  final PredictionResult result;
  const RiskCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.riskColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, spreadRadius: 2)],
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text('${result.riskEmoji}  ${result.risk} RISK',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const Spacer(),
            Text('${result.probability.toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: result.probability / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 10),
          if (result.location.isNotEmpty)
            Row(children: [
              const Icon(Icons.location_on, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(result.location, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ]),
          if (result.risk == 'HIGH') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('You are in a high-risk wildlife conflict zone! Be cautious.',
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
