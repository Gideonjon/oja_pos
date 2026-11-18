import 'package:flutter/material.dart';

import 'theme.dart';

class BillService {
  const BillService(this.id, this.name);

  /// VTpass serviceID.
  final String id;
  final String name;
}

class BillCategory {
  const BillCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.background,
    required this.services,
  });

  final String id; // airtime | data | tv | electricity
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color background;
  final List<BillService> services;
}

// Must stay in sync with CATALOG in worker/src/vtpass.js.
const List<BillCategory> billCategories = [
  BillCategory(
    id: 'airtime',
    title: 'Airtime',
    subtitle: 'MTN, Airtel, Glo, 9mobile',
    icon: Icons.phone_iphone_rounded,
    color: AppColors.primary,
    background: AppColors.primarySoft,
    services: [
      BillService('mtn', 'MTN'),
      BillService('airtel', 'Airtel'),
      BillService('glo', 'Glo'),
      BillService('etisalat', '9mobile'),
    ],
  ),
  BillCategory(
    id: 'data',
    title: 'Data',
    subtitle: 'Internet bundles',
    icon: Icons.wifi_rounded,
    color: AppColors.blue,
    background: AppColors.blueSoft,
    services: [
      BillService('mtn-data', 'MTN'),
      BillService('airtel-data', 'Airtel'),
      BillService('glo-data', 'Glo'),
      BillService('etisalat-data', '9mobile'),
    ],
  ),
  BillCategory(
    id: 'tv',
    title: 'TV',
    subtitle: 'DStv, GOtv, StarTimes',
    icon: Icons.tv_rounded,
    color: AppColors.purple,
    background: AppColors.purpleSoft,
    services: [
      BillService('dstv', 'DStv'),
      BillService('gotv', 'GOtv'),
      BillService('startimes', 'StarTimes'),
    ],
  ),
  BillCategory(
    id: 'electricity',
    title: 'Electricity',
    subtitle: 'Prepaid and postpaid',
    icon: Icons.lightbulb_rounded,
    color: AppColors.bitcoin,
    background: AppColors.bitcoinSoft,
    services: [
      BillService('ikeja-electric', 'Ikeja Electric'),
      BillService('eko-electric', 'Eko Electric'),
      BillService('abuja-electric', 'Abuja Electric'),
      BillService('kano-electric', 'Kano Electric'),
      BillService('portharcourt-electric', 'Port Harcourt Electric'),
      BillService('jos-electric', 'Jos Electric'),
      BillService('ibadan-electric', 'Ibadan Electric'),
      BillService('kaduna-electric', 'Kaduna Electric'),
      BillService('enugu-electric', 'Enugu Electric'),
      BillService('benin-electric', 'Benin Electric'),
      BillService('aba-electric', 'Aba Electric'),
      BillService('yola-electric', 'Yola Electric'),
    ],
  ),
];
