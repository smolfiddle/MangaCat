import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color background = Color(0xFF17171B);
  static const Color surface = Color(0xFF1F1F24);
  static const Color surfaceVariant = Color(0xFF26262C);
  static const Color accent = Color(0xFFE84E8A);
  static const Color accentPress = Color(0xFFF06A9C);
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFA0A0AA);
  static const Color statusReading = Color(0xFFE84E8A);
  static const Color statusCompleted = Color(0xFF4CC38A);
  static const Color statusPlanned = Color(0xFF8B8B94);
  static const Color statusDropped = Color(0xFFE05E5E);
  static const Color divider = Color(0xFF2E2E34);
}

abstract final class AppShape {
  static const double rowHeight = 64;
  static const double cardRadius = 12;
  static const double chipRadius = 8;
}

const String kAppVersion = '0.0.1';
const List<String> kDefaultScanExtensions = <String>['cbz'];
const int kProgressMaxChars = 40;
const int kNotesMaxChars = 500;
const int kAuditRetention = 500;
