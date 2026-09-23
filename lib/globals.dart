// ignore: unnecessary_library_name
library my_app.globals;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

List<String> arguments = [];
String? initUri;
PermissionStatus? storagePermissionStatus;
final moreMenuKey = GlobalKey<PopupMenuButtonState>();
final rateMenuKey = GlobalKey<PopupMenuButtonState>();
const double minZoom = 0.25;
const double maxZoom = 5.0;
const double zoomStep = 0.05;
const List<double> longPressSpeedStops = [
  1.25,
  1.5,
  1.75,
  2.0,
  2.5,
  3.0,
  4.0,
  5.0,
];
const List<double> speedStops = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  3.0,
  4.0,
  5.0,
  6.0,
  7.0,
  8.0,
  9.0,
  10.0,
];
