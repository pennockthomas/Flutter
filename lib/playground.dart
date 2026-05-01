import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PlaygroundScreen(),
    ));

enum NodeStatus { available, completed }

class Challenge {
  final String label;
  final String description;
  final List<String> unlocks;
  Challenge({required this.label, required this.description, required this.unlocks});
}

class Node {
  Offset position;
  Offset velocity = Offset.zero;
  final String label;
  String? rootCategory; 
  bool isExpanded = false;
  bool showContent = false;
  final bool isFixed;
  NodeStatus status;
  bool hasSpawnedChildren = false;

  Node({
    required this.position, 
    required this.label, 
    this.rootCategory,
    this.isFixed = false, 
    this.status = NodeStatus.available
  });
}

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});
  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> with TickerProviderStateMixin {
  late Ticker _physicsTicker;
  final TransformationController _transformController = TransformationController();
  
  late AnimationController _cameraController;
  Animation<Matrix4>? _cameraAnimation;

  List<Node> nodes = [];
  List<List<int>> connections = [];
  Map<String, Challenge> challengeData = {};
  bool isLoading = true;
  bool _showProgressMenu = false;

  final String userName = "Thomas Pennock";
  Map<String, int> categories = {}; 

  final double maxZoom = 4.0;      
  final double minZoom = 0.2;      
  final double canvasSize = 4000.0; 
  final double maxLinkDistance = 200.0; 
  final double targetLinkDistance = 120.0; 
  
  double _backgroundScale = 1.2;
  final double collapsedSize = 100.0;
  final double expandedSize = 220.0;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    
    _transformController.value = Matrix4.identity()
      ..translate(-(canvasSize / 2) + 200, -(canvasSize / 2) + 400);

    _physicsTicker = createTicker(_updatePhysics)..start();
    
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(() {
        if (_cameraAnimation != null) {
          _transformController.value = _cameraAnimation!.value;
        }
      });

    _transformController.addListener(() {
      double scale = _transformController.value.getMaxScaleOnAxis();
      setState(() {
        _backgroundScale = 1.2 + (scale - 1.0) * 0.15; 
      });
    });
  }

  Future<void> _loadInitialData() async {
    try {
      final String response = await rootBundle.loadString('assets/data/challenge.json');
      final List<dynamic> decodedData = jsonDecode(response);
      Map<String, Challenge> tempMap = {};
      for (var item in decodedData) {
        tempMap[item['id']] = Challenge(
          label: item['id'],
          description: item['description'],
          unlocks: List<String>.from(item['unlocks']),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      List<String> mainTiers = tempMap["Start"]?.unlocks ?? [];
      Map<String, int> dynamicCategories = {};
      for (var tier in mainTiers) {
        dynamicCategories[tier] = prefs.getInt('progress_$tier') ?? 0;
      }

      setState(() {
        challengeData = tempMap;
        categories = dynamicCategories;
        isLoading = false;
        nodes = [Node(position: Offset(canvasSize / 2, canvasSize / 2), label: "Start", isFixed: true)];
      });

      List<String> savedUnlocked = prefs.getStringList('unlocked_nodes') ?? [];
      for (String label in savedUnlocked) {
        int idx = nodes.indexWhere((n) => n.label == label);
        if (idx != -1) _spawnNextTier(idx, isRestoring: true); 
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateCategoryProgress(String category) async {
    if (!categories.containsKey(category)) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      int currentVal = categories[category] ?? 0;
      categories[category] = (currentVal + 1).clamp(0, 10);
    });
    await prefs.setInt('progress_$category', categories[category]!);
  }

  void _centerOnNode(Node node, {bool animateZoom = true, bool isClosing = false}) {
    final size = MediaQuery.of(context).size;
    double multiplier = isClosing ? 1.6 : 1.2;
    double targetScale = (size.width / (expandedSize * multiplier)).clamp(minZoom, maxZoom);

    final double targetX = (size.width / 2) - (node.position.dx * targetScale);
    final double targetY = (size.height / 2) - (node.position.dy * targetScale);

    final Matrix4 endMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(targetScale);

    if (animateZoom) {
      _cameraAnimation = Matrix4Tween(
        begin: _transformController.value,
        end: endMatrix,
      ).animate(CurvedAnimation(parent: _cameraController, curve: Curves.easeInOutCubic));
      _cameraController.forward(from: 0);
    } else {
      _transformController.value = endMatrix;
    }
  }

  void _spawnNextTier(int parentIdx, {bool isRestoring = false}) async {
    if (nodes[parentIdx].hasSpawnedChildren) return;
    final parentNode = nodes[parentIdx];
    String currentLabel = parentNode.label;

    if (!isRestoring) {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList('unlocked_nodes') ?? [];
      if (!history.contains(currentLabel)) {
        history.add(currentLabel);
        await prefs.setStringList('unlocked_nodes', history);
      }
      if (parentNode.rootCategory != null) _updateCategoryProgress(parentNode.rootCategory!);
    }

    setState(() {
      parentNode.status = NodeStatus.completed;
      parentNode.hasSpawnedChildren = true;
      parentNode.showContent = false;
      parentNode.isExpanded = false;

      if (!isRestoring) _centerOnNode(parentNode, isClosing: true);

      List<String> toUnlock = challengeData[currentLabel]?.unlocks ?? [];
      for (var title in toUnlock) {
        if (!nodes.any((n) => n.label == title)) {
          String? childCategory = (parentNode.label == "Start") ? title : parentNode.rootCategory;
          nodes.add(Node(
            position: parentNode.position + Offset(_random.nextDouble()*40, _random.nextDouble()*40), 
            label: title,
            rootCategory: childCategory,
          ));
          connections.add([parentIdx, nodes.length - 1]);
        }
      }
    });
  }

  void _updatePhysics(Duration elapsed) {
    if (isLoading || nodes.isEmpty) return;
    setState(() {
      for (int i = 0; i < nodes.length; i++) {
        for (int j = 0; j < nodes.length; j++) {
          if (i == j) continue;
          Offset diff = nodes[i].position - nodes[j].position;
          double dist = diff.distance.clamp(1.0, 1000.0);
          nodes[i].velocity += (diff / dist) * (600.0 / dist);
        }
      }

      for (var conn in connections) {
        Node n1 = nodes[conn[0]], n2 = nodes[conn[1]];
        Offset diff = n1.position - n2.position;
        double dist = diff.distance;
        Offset force = (diff / dist) * ((dist - targetLinkDistance) * 0.09); 
        if (!n1.isFixed) n1.velocity -= force;
        if (!n2.isFixed) n2.velocity += force;

        if (dist > maxLinkDistance) {
          Offset overExtend = diff - ((diff / dist) * maxLinkDistance);
          if (n1.isFixed) n2.position += overExtend;
          else { n1.position -= overExtend * 0.5; n2.position += overExtend * 0.5; }
        }
      }

      Node? expandedNode;
      for (var node in nodes) {
        if (!node.isFixed) node.position += node.velocity;
        node.velocity *= 0.45;
        if (node.isExpanded) expandedNode = node;
      }

      if (expandedNode != null && !_cameraController.isAnimating) {
        final size = MediaQuery.of(context).size;
        double currentScale = _transformController.value.getMaxScaleOnAxis();
        final double targetX = (size.width / 2) - (expandedNode.position.dx * currentScale);
        final double targetY = (size.height / 2) - (expandedNode.position.dy * currentScale);
        _transformController.value = Matrix4.identity()..translate(targetX, targetY)..scale(currentScale);
      }
    });
  }

@override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Transform.scale(
              scale: _backgroundScale,
              child: Image.asset(
                'assets/background.jpg', 
                fit: BoxFit.cover, 
                errorBuilder: (c,e,s) => Container(color: Colors.blueGrey[900])
              ),
            ),
          ),

          // Darkening Overlay Layer (Set to 0.2)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.2),
            ),
          ),
          
          InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity), 
            minScale: minZoom,
            maxScale: maxZoom,
            child: SizedBox(
              width: canvasSize,
              height: canvasSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(painter: GraphPainter(nodes, connections), size: Size.infinite),
                  ...nodes.asMap().entries.map((entry) => _buildPhysicsNode(entry.key, entry.value)).toList(),
                ],
              ),
            ),
          ),

          // ✅ Top Left: Go Back Button (Settings Style)
          Positioned(
            top: 50, 
            left: 10, 
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ✅ Top Right: Reset Button
          Positioned(
            top: 50, 
            right: 20, 
            child: Opacity(
              opacity: 0.5, 
              child: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 28), 
                onPressed: () async { 
                  (await SharedPreferences.getInstance()).clear(); 
                }
              ),
            ),
          ),

          _buildProgressMenu(),
        ],
      ),
    );
  }

  Widget _buildProgressMenu() {
    int totalLevel = categories.values.fold(0, (sum, val) => sum + val);
    return Positioned(
      bottom: 20, right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: _showProgressMenu 
              ? Container(
                  width: 240, margin: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            const Divider(color: Colors.white24, height: 20),
                            ...categories.entries.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text("${e.value}/10", style: const TextStyle(color: Colors.white70, fontSize: 10))]),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(value: e.value / 10, backgroundColor: Colors.white12, color: Colors.greenAccent.withOpacity(0.6), minHeight: 4),
                                ],
                              ),
                            )).toList(),
                            const Divider(color: Colors.white24, height: 20),
                            Text("Overall Level: $totalLevel", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ) : const SizedBox.shrink(),
          ),
          GestureDetector(
            onTap: () => setState(() => _showProgressMenu = !_showProgressMenu),
            child: Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
              child: AnimatedRotation(duration: const Duration(milliseconds: 300), turns: _showProgressMenu ? 0.5 : 0, child: const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 30)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicsNode(int idx, Node node) {
    double targetSize = node.isExpanded ? expandedSize : collapsedSize;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: collapsedSize, end: targetSize),
      onEnd: () { if (node.isExpanded) setState(() => node.showContent = true); },
      builder: (context, animSize, child) {
        return Positioned(
          left: node.position.dx - (animSize / 2),
          top: node.position.dy - (animSize / 2),
          child: GestureDetector(
            onPanUpdate: (d) => setState(() { node.position += d.delta; node.velocity = Offset.zero; }),
            onTap: () {
              setState(() {
                if (node.isExpanded) {
                  node.showContent = false; node.isExpanded = false; _centerOnNode(node, isClosing: true);
                } else {
                  for (var n in nodes) { n.isExpanded = false; n.showContent = false; }
                  node.isExpanded = true; _centerOnNode(node, isClosing: false);
                }
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(node.isExpanded ? 30 : animSize / 2),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: animSize, height: animSize, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: node.status == NodeStatus.completed ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(node.isExpanded ? 30 : animSize / 2),
                    border: Border.all(color: node.status == NodeStatus.completed ? Colors.green.withOpacity(0.4) : Colors.white.withOpacity(0.25)),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: node.showContent 
                          ? SingleChildScrollView(
                              key: const ValueKey("expanded"),
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(node.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                  const SizedBox(height: 10),
                                  Text(challengeData[node.label]?.description ?? "...", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 15),
                                  if (!node.hasSpawnedChildren)
                                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white), onPressed: () => _spawnNextTier(idx), child: const Text("Unlock Tier"))
                                  else
                                    const Icon(Icons.check_circle, color: Colors.green, size: 30),
                                ],
                              ),
                            )
                          : Container(alignment: Alignment.center, key: const ValueKey("collapsed"), child: Text(node.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() { 
    _physicsTicker.dispose(); 
    _cameraController.dispose();
    _transformController.dispose(); 
    super.dispose(); 
  }
}

class GraphPainter extends CustomPainter {
  final List<Node> nodes;
  final List<List<int>> connections;
  GraphPainter(this.nodes, this.connections);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.15)..strokeWidth = 6;
    for (var c in connections) canvas.drawLine(nodes[c[0]].position, nodes[c[1]].position, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}