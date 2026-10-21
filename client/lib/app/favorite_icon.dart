import 'package:flutter/material.dart';

Color savedHeartColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.redAccent.shade100
    : Colors.red.shade700;
