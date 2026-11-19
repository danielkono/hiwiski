import 'package:flutter/material.dart';

// The store pictures' colours and type, shared by the pictures and the feature
// graphic.

const storeBackground = Color(0xFFE8EEDB);
const storeSurface = Color(0xFFF8FAF0);
const storeInk = Color(0xFF1B2A1A);
const storeSubline = Color(0xFF4B5A49);
const storePillInk = Color(0xFF2C3A2B);
const storePillBorder = Color(0xFFC2C8BD);
const storeFrame = Color(0xFF1E251D);
const storeFrameEdge = Color(0xFF3A4538);
const storeShadow = Color(0xFF20301E);

/// A CSS blur — twice the Gaussian's sigma — as Flutter's blur radius.
double cssBlur(double css) => (css / 2 - 0.5) / 0.57735;

/// Roboto is a variable font: the weight goes on the `wght` axis as well.
TextStyle roboto(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
  double? letterSpacing,
}) => .new(
  fontFamily: 'Roboto',
  fontSize: size,
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  // As CSS spreads line height: half above, half below.
  leadingDistribution: .even,
);
