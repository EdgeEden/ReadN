import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Adapter that remaps Android Stylus pointer data to mouse pointer data
/// when Stylus Mode is enabled, allowing Flutter's SelectionArea / SelectableRegion
/// to perform smooth, continuous highlighter-style drag-to-select without requiring
/// a 500ms long press.
class StylusPointerAdapter {
  static bool _initialized = false;
  static bool isStylusModeActive = false;
  static bool isCurrentPointerTouch = false;
  static bool isCurrentPointerStylus = false;
  static bool isStylusContacting = false;
  static DateTime? lastStylusContactTime;

  /// Check whether the given [kind] represents a stylus input.
  /// If [isStylusModeActive] is true on Android, remapped [PointerDeviceKind.mouse]
  /// that originated from a physical stylus will also return true.
  static bool isStylus(ui.PointerDeviceKind? kind) {
    if (kind == null) return false;
    if (kind == ui.PointerDeviceKind.stylus || kind == ui.PointerDeviceKind.invertedStylus) {
      return true;
    }
    if (isStylusModeActive && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (kind == ui.PointerDeviceKind.mouse && isCurrentPointerStylus) {
        return true;
      }
    }
    return false;
  }

  /// Check whether the given [kind] represents a touch input.
  static bool isTouch(ui.PointerDeviceKind? kind) {
    if (kind == null) return false;
    return kind == ui.PointerDeviceKind.touch;
  }

  /// Check whether palm rejection is currently active.
  /// Only applies to touch pointers in stylus mode!
  static bool isPalmRejectionActive(bool stylusMode, {ui.PointerDeviceKind? kind}) {
    if (!stylusMode) return false;
    if (kind != null && !isTouch(kind)) {
      return false; // Stylus or mouse is never palm-rejected
    }
    if (isStylusContacting) return true;
    if (lastStylusContactTime != null) {
      return DateTime.now().difference(lastStylusContactTime!).inMilliseconds < 500;
    }
    return false;
  }

  static void init() {
    if (_initialized) return;
    _initialized = true;

    final originalCallback = PlatformDispatcher.instance.onPointerDataPacket;
    PlatformDispatcher.instance.onPointerDataPacket = (ui.PointerDataPacket packet) {
      if (isStylusModeActive && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        bool hasStylus = false;
        bool hasTouch = false;

        for (final datum in packet.data) {
          if (datum.kind == ui.PointerDeviceKind.stylus ||
              datum.kind == ui.PointerDeviceKind.invertedStylus) {
            hasStylus = true;
          } else if (datum.kind == ui.PointerDeviceKind.touch) {
            hasTouch = true;
          }
        }

        if (hasStylus) {
          isCurrentPointerStylus = true;
          isCurrentPointerTouch = false;
          for (final datum in packet.data) {
            if (datum.kind == ui.PointerDeviceKind.stylus ||
                datum.kind == ui.PointerDeviceKind.invertedStylus) {
              if (datum.change == ui.PointerChange.down || datum.change == ui.PointerChange.move) {
                isStylusContacting = true;
                lastStylusContactTime = DateTime.now();
              } else if (datum.change == ui.PointerChange.up || datum.change == ui.PointerChange.cancel) {
                isStylusContacting = false;
                lastStylusContactTime = DateTime.now();
              }
            }
          }
        } else if (hasTouch) {
          isCurrentPointerTouch = true;
          isCurrentPointerStylus = false;
        } else {
          isCurrentPointerTouch = false;
          isCurrentPointerStylus = false;
        }

        if (hasStylus) {
          final mappedData = packet.data.map((datum) {
            if (datum.kind == ui.PointerDeviceKind.stylus ||
                datum.kind == ui.PointerDeviceKind.invertedStylus) {
              int buttons = datum.buttons;
              // Ensure primary mouse button is reported when stylus is contacting the screen
              if (datum.change == ui.PointerChange.down || datum.change == ui.PointerChange.move) {
                if (buttons == 0) buttons = 1;
              }
              return ui.PointerData(
                viewId: datum.viewId,
                embedderId: datum.embedderId,
                timeStamp: datum.timeStamp,
                change: datum.change,
                kind: ui.PointerDeviceKind.mouse, // Remap to mouse so Flutter drag-select activates!
                signalKind: datum.signalKind,
                device: datum.device,
                pointerIdentifier: datum.pointerIdentifier,
                physicalX: datum.physicalX,
                physicalY: datum.physicalY,
                physicalDeltaX: datum.physicalDeltaX,
                physicalDeltaY: datum.physicalDeltaY,
                buttons: buttons,
                obscured: datum.obscured,
                synthesized: datum.synthesized,
                pressure: datum.pressure,
                pressureMin: datum.pressureMin,
                pressureMax: datum.pressureMax,
                distance: datum.distance,
                distanceMax: datum.distanceMax,
                size: datum.size,
                radiusMajor: datum.radiusMajor,
                radiusMinor: datum.radiusMinor,
                radiusMin: datum.radiusMin,
                radiusMax: datum.radiusMax,
                orientation: datum.orientation,
                tilt: datum.tilt,
                platformData: datum.platformData,
                scrollDeltaX: datum.scrollDeltaX,
                scrollDeltaY: datum.scrollDeltaY,
              );
            }
            return datum;
          }).toList();

          originalCallback?.call(ui.PointerDataPacket(data: mappedData));
          return;
        }
      } else {
        // Track touch vs non-touch pointers for filtering in non-stylus mode or non-android platforms
        for (final datum in packet.data) {
          if (datum.kind == ui.PointerDeviceKind.touch) {
            isCurrentPointerTouch = true;
            isCurrentPointerStylus = false;
          } else if (datum.kind == ui.PointerDeviceKind.stylus ||
                     datum.kind == ui.PointerDeviceKind.invertedStylus) {
            isCurrentPointerTouch = false;
            isCurrentPointerStylus = true;
            if (datum.change == ui.PointerChange.down || datum.change == ui.PointerChange.move) {
              isStylusContacting = true;
              lastStylusContactTime = DateTime.now();
            } else if (datum.change == ui.PointerChange.up || datum.change == ui.PointerChange.cancel) {
              isStylusContacting = false;
              lastStylusContactTime = DateTime.now();
            }
          } else {
            isCurrentPointerTouch = false;
            isCurrentPointerStylus = false;
          }
        }
      }

      originalCallback?.call(packet);
    };
  }
}

/// Widget that filters touch events from hitting SelectionArea in stylus mode,
/// ensuring that fingers are purely used for scrolling/zooming while the stylus
/// is used for text selection and annotations.
class StylusSelectionFilter extends SingleChildRenderObjectWidget {
  final bool filterTouch;

  const StylusSelectionFilter({
    super.key,
    required this.filterTouch,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderStylusSelectionFilter(filterTouch: filterTouch);
  }

  @override
  void updateRenderObject(BuildContext context, RenderStylusSelectionFilter renderObject) {
    renderObject.filterTouch = filterTouch;
  }
}

class RenderStylusSelectionFilter extends RenderProxyBox {
  bool filterTouch;

  RenderStylusSelectionFilter({required this.filterTouch});

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (filterTouch && StylusPointerAdapter.isCurrentPointerTouch) {
      // Do not hit-test SelectionArea for touch events in stylus mode!
      // This allows touch events to directly pass to ancestor Scrollables (ListView)
      // for scrolling/zooming without accidentally selecting text.
      return false;
    }
    return super.hitTestChildren(result, position: position);
  }
}

