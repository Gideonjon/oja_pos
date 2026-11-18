import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/wallet.dart';
import 'bills_screen.dart';
import 'charge_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';

/// Frame for the signed-in app: bottom navigation on phones, a sidebar on
/// wide screens (web and desktop).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Wallet.instance.load(Db.uid);
  }

  void _go(int index) => setState(() => _index = index);

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Charge'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Bills'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _index,
      children: [
        HomeScreen(onNavigate: _go),
        const ChargeScreen(),
        const BillsScreen(),
        const MoreScreen(),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 900) {
          // Web / desktop: sidebar navigation, content at a readable width.
          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: Row(
              children: [
                Container(
                  width: 248,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: AppColors.line)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 32),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Image.asset('assets/brand/wordmark.png', height: 40, semanticLabel: 'Oja'),
                        ),
                      ),
                      for (var i = 0; i < _tabs.length; i++)
                        _SideItem(
                          icon: _index == i ? _tabs[i].$2 : _tabs[i].$1,
                          label: _tabs[i].$3,
                          selected: _index == i,
                          onTap: () => _go(i),
                        ),
                    ],
                  ),
                ),
                Expanded(child: Narrow(maxWidth: 640, child: pages)),
              ],
            ),
          );
        }
        return Scaffold(
          // Tabs handle their own keyboard insets; keeps the till layout stable.
          resizeToAvoidBottomInset: false,
          body: pages,
          bottomNavigationBar: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE8EAEE))),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 22, color: selected ? AppColors.primary : AppColors.muted),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
