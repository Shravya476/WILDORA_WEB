import 'package:flutter/material.dart';
import 'login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const forest = Color(0xFF0B2616);
  static const green = Color(0xFF2F8F3A);
  static const lime = Color(0xFF86C95A);
  static const cream = Color(0xFFF7F4EC);

  void _openLogin(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: cream,
      body: SingleChildScrollView(child: Column(children: [
        _hero(context, wide),
        _featureStrip(),
        _wildlifeGallery(wide),
        _missionSection(wide),
        _howItWorks(),
        _footer(wide),
      ])),
    );
  }

  Widget _hero(BuildContext context, bool wide) => Container(
    constraints: const BoxConstraints(minHeight: 680),
    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF163C20), Color(0xFF071A0D)])),
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: ForestPainter())),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 64 : 24, vertical: 22),
        child: Column(children: [
          Row(children: [
            const _Brand(),
            const Spacer(),
            if (wide) ...[_nav('Home'), _nav('About'), _nav('Features'), _nav('Blog'), _nav('Contact'), const SizedBox(width: 10)],
            FilledButton(onPressed: () => _openLogin(context), style: FilledButton.styleFrom(backgroundColor: green, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))), child: const Text('Get Started')),
          ]),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 70, bottom: 35), child: wide ? Row(children: [Expanded(child: _heroCopy(context)), Expanded(child: _animalArtwork())]) : Column(children: [const SizedBox(height: 35), _heroCopy(context), const SizedBox(height: 30), _animalArtwork()]))),
        ]),
      ),
    ]),
  );

  Widget _heroCopy(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7), decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(20)), child: const Text('🌿  TECHNOLOGY FOR WILDLIFE', style: TextStyle(color: lime, fontSize: 12, fontWeight: FontWeight.w700))),
    const SizedBox(height: 24),
    const Text('Smart Wildlife', style: TextStyle(color: Colors.white, fontSize: 54, height: 1.0, fontWeight: FontWeight.w800)),
    const Text('Safer Communities', style: TextStyle(color: lime, fontSize: 54, height: 1.05, fontWeight: FontWeight.w800)),
    const SizedBox(height: 20),
    const Text('WILDORA uses intelligent technology and real-time location data to help predict, prevent and manage human-wildlife conflict.', style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.65)),
    const SizedBox(height: 28),
    Wrap(spacing: 12, runSpacing: 12, children: [
      FilledButton(onPressed: () => _openLogin(context), style: FilledButton.styleFrom(backgroundColor: green, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15)), child: const Text('Get Started')),
      OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70), padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15)), child: const Text('Learn More')),
    ]),
  ]);

  Widget _animalArtwork() => Container(
    height: 380,
    constraints: const BoxConstraints(maxWidth: 520),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(.10)), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x334F7C4D), Color(0x00101F13)])),
    child: Stack(children: [
      Positioned(left: 22, top: 22, child: Icon(Icons.eco, size: 110, color: Colors.white.withOpacity(.05))),
      Positioned(right: 25, bottom: 20, child: Icon(Icons.eco, size: 160, color: Colors.white.withOpacity(.05))),
      const Center(child: Text('🐘', style: TextStyle(fontSize: 150))),
      const Positioned(right: 35, bottom: 12, child: Text('🐅', style: TextStyle(fontSize: 105))),
      const Positioned(left: 35, bottom: 28, child: Text('🌿', style: TextStyle(fontSize: 90))),
      const Positioned(right: 120, top: 35, child: Text('🦅', style: TextStyle(fontSize: 35))),
    ]),
  );


  Widget _wildlifeGallery(bool wide) => Container(
    padding: EdgeInsets.symmetric(horizontal: wide ? 70 : 24, vertical: 70),
    color: const Color(0xFFF1F4EA),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('MEET THE WILDLIFE', style: TextStyle(color: green, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      const Text('Real wildlife. Real places. Smarter protection.', style: TextStyle(color: forest, fontSize: 34, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Text('WILDORA helps communities understand and respond to wildlife movement around forest boundaries.', style: TextStyle(color: Colors.black54, fontSize: 15, height: 1.6)),
      const SizedBox(height: 28),
      LayoutBuilder(builder: (context, c) {
        final count = c.maxWidth >= 900 ? 3 : c.maxWidth >= 560 ? 2 : 1;
        final gap = 18.0;
        final width = (c.maxWidth - gap * (count - 1)) / count;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          _PhotoAnimalCard(width: width, name: 'Asian Elephant', caption: 'Forest corridors & crop areas', url: 'https://images.unsplash.com/photo-1557050543-4d5f4e07ef46?auto=format&fit=crop&w=1000&q=85'),
          _PhotoAnimalCard(width: width, name: 'Tiger', caption: 'Predator movement near forest edges', url: 'https://images.unsplash.com/photo-1561731216-c3a4d99437d5?auto=format&fit=crop&w=1000&q=85'),
          _PhotoAnimalCard(width: width, name: 'Leopard', caption: 'Adaptable wildlife near communities', url: 'https://images.unsplash.com/photo-1549366021-9f761d450615?auto=format&fit=crop&w=1000&q=85'),
        ]);
      }),
    ]),
  );

  Widget _featureStrip() => Container(color: const Color(0xFF12371C), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20), child: Wrap(alignment: WrapAlignment.center, spacing: 35, runSpacing: 18, children: const [
    _Feature(icon: Icons.analytics_outlined, title: 'Predict Risk', text: 'AI-powered risk predictions for locations.'),
    _Feature(icon: Icons.notifications_active_outlined, title: 'Real-time Alerts', text: 'Stay informed about wildlife movement.'),
    _Feature(icon: Icons.forest_outlined, title: 'Protect Together', text: 'Help communities and wildlife coexist.'),
  ]));

  Widget _missionSection(bool wide) => Container(padding: EdgeInsets.symmetric(horizontal: wide ? 100 : 25, vertical: 80), child: wide ? Row(children: [Expanded(child: _missionText()), const SizedBox(width: 70), Expanded(child: _missionCard())]) : Column(children: [_missionText(), const SizedBox(height: 30), _missionCard()]));

  Widget _missionText() => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('WHY WILDORA?', style: TextStyle(color: green, fontWeight: FontWeight.bold, letterSpacing: 1.4)), SizedBox(height: 12), Text('Technology for coexistence.', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: forest)), SizedBox(height: 15), Text('Human-wildlife conflict affects both people and animals. WILDORA brings prediction, location intelligence and safety information together in one simple platform.', style: TextStyle(color: Colors.black54, height: 1.7, fontSize: 16))]);

  Widget _missionCard() => Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: const Color(0xFFE4EEDC), borderRadius: BorderRadius.circular(28)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.pets, color: green, size: 42), SizedBox(height: 18), Text('Predict • Prevent • Protect', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: forest)), SizedBox(height: 10), Text('From a single location prediction to a complete wildlife safety dashboard, WILDORA is designed around practical decision-making.', style: TextStyle(color: Colors.black54, height: 1.6))]));

  Widget _howItWorks() => Container(color: forest, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 70), child: Column(children: [const Text('How WILDORA Works', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)), const SizedBox(height: 35), Wrap(alignment: WrapAlignment.center, spacing: 20, runSpacing: 20, children: const [_Step(number: '01', title: 'Choose a location', icon: Icons.location_on_outlined), _Step(number: '02', title: 'AI predicts risk', icon: Icons.auto_graph), _Step(number: '03', title: 'Take safer action', icon: Icons.shield_outlined)])]));

  Widget _footer(bool wide) => Container(color: const Color(0xFF06140A), padding: EdgeInsets.symmetric(horizontal: wide ? 65 : 25, vertical: 45), child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 55, runSpacing: 35, children: const [
    SizedBox(width: 250, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_Brand(), SizedBox(height: 12), Text('Smart Wildlife • Safer Communities', style: TextStyle(color: Colors.white70)), SizedBox(height: 12), Text('Empowering technology and communities to coexist with wildlife.', style: TextStyle(color: Colors.white54, height: 1.5))])),
    _FooterColumn(title: 'Quick Links', items: ['Home', 'About Us', 'Features', 'Blog', 'Contact']),
    _FooterColumn(title: 'Guidelines', items: ['Wildlife Guide', 'Safety Tips', 'Research', 'FAQs']),
    _FooterColumn(title: 'Support', items: ['Help Center', 'Report an Issue', 'Privacy Policy', 'Terms of Use']),
  ]));

  Widget _nav(String text) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)));
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.pets, size: 29, color: Colors.white), SizedBox(width: 8), Text('WILDORA', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: 1.2))]);
}

class _Feature extends StatelessWidget {
  final IconData icon; final String title; final String text;
  const _Feature({required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) => SizedBox(width: 285, child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(.08), shape: BoxShape.circle), child: Icon(icon, color: const Color(0xFF86C95A))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text(text, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4))]))]));
}

class _Step extends StatelessWidget {
  final String number; final String title; final IconData icon;
  const _Step({required this.number, required this.title, required this.icon});
  @override
  Widget build(BuildContext context) => Container(width: 250, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(number, style: const TextStyle(color: Color(0xFF86C95A), fontWeight: FontWeight.bold)), const SizedBox(height: 20), Icon(icon, color: Colors.white, size: 30), const SizedBox(height: 15), Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17))]));
}

class _FooterColumn extends StatelessWidget {
  final String title; final List<String> items;
  const _FooterColumn({required this.title, required this.items});
  @override
  Widget build(BuildContext context) => SizedBox(width: 140, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 14), ...items.map((e) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Text(e, style: const TextStyle(color: Colors.white54, fontSize: 12))))]));
}

class ForestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(.025);
    for (var i = 0; i < 14; i++) {
      final x = (i * 83.0) % size.width;
      final h = 100.0 + (i % 5) * 35;
      final path = Path()..moveTo(x, size.height)..lineTo(x + 35, size.height - h)..lineTo(x + 70, size.height)..close();
      canvas.drawPath(path, p);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class _PhotoAnimalCard extends StatelessWidget {
  final double width;
  final String name, caption, url;
  const _PhotoAnimalCard({required this.width, required this.name, required this.caption, required this.url});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(children: [
        AspectRatio(aspectRatio: 1.45, child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFDDEBD3), child: const Icon(Icons.pets, size: 70, color: Color(0xFF6D8C63)))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(.78)])))),
        Positioned(left: 18, right: 18, bottom: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(caption, style: const TextStyle(color: Colors.white70, fontSize: 11))])),
      ]),
    ),
  );
}
