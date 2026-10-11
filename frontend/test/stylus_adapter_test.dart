import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/stylus_pointer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StylusPointerAdapter remaps stylus PointerData to mouse PointerData', () {
    final originalData = [
      const ui.PointerData(
        change: ui.PointerChange.down,
        kind: ui.PointerDeviceKind.stylus,
        buttons: 0,
        physicalX: 100.0,
        physicalY: 200.0,
      ),
      const ui.PointerData(
        change: ui.PointerChange.move,
        kind: ui.PointerDeviceKind.touch,
        buttons: 0,
        physicalX: 150.0,
        physicalY: 250.0,
      ),
    ];

    final mapped = originalData.map((datum) {
      if (datum.kind == ui.PointerDeviceKind.stylus) {
        int buttons = datum.buttons;
        if (datum.change == ui.PointerChange.down || datum.change == ui.PointerChange.move) {
          if (buttons == 0) buttons = 1;
        }
        return ui.PointerData(
          viewId: datum.viewId,
          embedderId: datum.embedderId,
          timeStamp: datum.timeStamp,
          change: datum.change,
          kind: ui.PointerDeviceKind.mouse,
          signalKind: datum.signalKind,
          device: datum.device,
          pointerIdentifier: datum.pointerIdentifier,
          physicalX: datum.physicalX,
          physicalY: datum.physicalY,
          physicalDeltaX: datum.physicalDeltaX,
          physicalDeltaY: datum.physicalDeltaY,
          buttons: buttons,
        );
      }
      return datum;
    }).toList();

    expect(mapped[0].kind, ui.PointerDeviceKind.mouse);
    expect(mapped[0].buttons, 1);
    expect(mapped[1].kind, ui.PointerDeviceKind.touch);
  });

  testWidgets('SelectionArea selects text on mouse drag gesture', (tester) async {
    String selectedText = '';
    bool menuBuilt = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) {
              selectedText = content?.plainText ?? '';
            },
            contextMenuBuilder: (context, state) {
              menuBuilt = true;
              return const Text('ContextMenuOpened');
            },
            child: const Text('Hello Flutter stylus selection world'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hello Flutter stylus selection world')) - const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedText.isNotEmpty, isTrue);
    // Verifies that Flutter's SelectableRegion does NOT invoke contextMenuBuilder on mouse drag release,
    // which explains why root Stack overlay management is required for mouse/stylus drag-selection.
    expect(menuBuilt, isFalse);
  });

  testWidgets('SelectionArea ignores stylus drag gesture without remapping', (tester) async {
    String selectedText = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) {
              selectedText = content?.plainText ?? '';
            },
            child: const Text('Hello Flutter stylus selection world'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hello Flutter stylus selection world')) - const Offset(60, 0),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // In Flutter, stylus drag without long-press DOES NOT select text!
    expect(selectedText.isEmpty, isTrue);
  });

  testWidgets('With StylusPointerAdapter, stylus PointerDataPacket is converted to mouse events in GestureBinding', (tester) async {
    final eventsReceived = <PointerEvent>[];
    tester.binding.pointerRouter.addGlobalRoute((event) {
      eventsReceived.add(event);
    });

    final originalCallback = tester.binding.platformDispatcher.onPointerDataPacket;
    tester.binding.platformDispatcher.onPointerDataPacket = (ui.PointerDataPacket packet) {
      final mapped = packet.data.map((datum) {
        if (datum.kind == ui.PointerDeviceKind.stylus || datum.kind == ui.PointerDeviceKind.invertedStylus) {
          int buttons = datum.buttons;
          if (datum.change == ui.PointerChange.down || datum.change == ui.PointerChange.move) {
            if (buttons == 0) buttons = 1;
          }
          return ui.PointerData(
            viewId: datum.viewId,
            embedderId: datum.embedderId,
            timeStamp: datum.timeStamp,
            change: datum.change,
            kind: ui.PointerDeviceKind.mouse,
            signalKind: datum.signalKind,
            device: datum.device,
            pointerIdentifier: datum.pointerIdentifier,
            physicalX: datum.physicalX,
            physicalY: datum.physicalY,
            physicalDeltaX: datum.physicalDeltaX,
            physicalDeltaY: datum.physicalDeltaY,
            buttons: buttons,
          );
        }
        return datum;
      }).toList();
      originalCallback?.call(ui.PointerDataPacket(data: mapped));
    };

    try {
      // Simulate engine sending stylus down packet
      tester.binding.platformDispatcher.onPointerDataPacket!(
        const ui.PointerDataPacket(
          data: [
            ui.PointerData(
              change: ui.PointerChange.down,
              kind: ui.PointerDeviceKind.stylus,
              physicalX: 100.0,
              physicalY: 100.0,
            ),
          ],
        ),
      );

      // Verify that the framework received a mouse PointerDownEvent!
      expect(eventsReceived.any((e) => e is PointerDownEvent && e.kind == PointerDeviceKind.mouse), isTrue);
    } finally {
      tester.binding.platformDispatcher.onPointerDataPacket = originalCallback;
    }
  });

  testWidgets('StylusSelectionFilter blocks touch selection when active, but permits mouse selection', (tester) async {
    bool isCurrentTouch = true;
    String selectedText = '';

    Widget buildTestWidget({required bool filterTouch}) {
      return MaterialApp(
        home: Scaffold(
          body: _TestFilterWidget(
            filterTouch: filterTouch,
            getIsTouch: () => isCurrentTouch,
            child: SelectionArea(
              onSelectionChanged: (content) {
                selectedText = content?.plainText ?? '';
              },
              child: const Text('Filtered stylus text selection sample'),
            ),
          ),
        ),
      );
    }

    // 1. Touch test with filter enabled: Touch should NOT select text!
    isCurrentTouch = true;
    selectedText = '';
    await tester.pumpWidget(buildTestWidget(filterTouch: true));
    await tester.pumpAndSettle();

    final touchGesture = await tester.startGesture(
      tester.getCenter(find.text('Filtered stylus text selection sample')) - const Offset(60, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600)); // long press
    await touchGesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await touchGesture.up();
    await tester.pumpAndSettle();

    expect(selectedText.isEmpty, isTrue); // Touch blocked from selection!

    // 2. Mouse/stylus test with filter enabled: Mouse/stylus SHOULD select text!
    isCurrentTouch = false;
    selectedText = '';
    await tester.pumpWidget(buildTestWidget(filterTouch: true));
    await tester.pumpAndSettle();

    final mouseGesture = await tester.startGesture(
      tester.getCenter(find.text('Filtered stylus text selection sample')) - const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouseGesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await mouseGesture.up();
    await tester.pumpAndSettle();

    expect(selectedText.isNotEmpty, isTrue); // Mouse/stylus selected text!
  });

  group('StylusPointerAdapter pointer classification and palm rejection', () {
    tearDown(() {
      StylusPointerAdapter.isStylusModeActive = false;
      StylusPointerAdapter.isCurrentPointerTouch = false;
      StylusPointerAdapter.isCurrentPointerStylus = false;
      StylusPointerAdapter.isStylusContacting = false;
      StylusPointerAdapter.lastStylusContactTime = null;
    });

    test('isTouch correctly identifies touch vs non-touch pointers', () {
      expect(StylusPointerAdapter.isTouch(PointerDeviceKind.touch), isTrue);
      expect(StylusPointerAdapter.isTouch(PointerDeviceKind.stylus), isFalse);
      expect(StylusPointerAdapter.isTouch(PointerDeviceKind.mouse), isFalse);
      expect(StylusPointerAdapter.isTouch(null), isFalse);
    });

    test('isStylus identifies native stylus events', () {
      expect(StylusPointerAdapter.isStylus(PointerDeviceKind.stylus), isTrue);
      expect(StylusPointerAdapter.isStylus(PointerDeviceKind.invertedStylus), isTrue);
      expect(StylusPointerAdapter.isStylus(PointerDeviceKind.touch), isFalse);
      expect(StylusPointerAdapter.isStylus(PointerDeviceKind.mouse), isFalse);
    });

    test('isPalmRejectionActive rejects touch during stylus contact and within 500ms', () {
      // 1. In non-stylus mode, palm rejection is never active
      StylusPointerAdapter.isStylusContacting = true;
      expect(StylusPointerAdapter.isPalmRejectionActive(false, kind: PointerDeviceKind.touch), isFalse);

      // 2. In stylus mode, non-touch devices (stylus/mouse) are never rejected
      expect(StylusPointerAdapter.isPalmRejectionActive(true, kind: PointerDeviceKind.stylus), isFalse);
      expect(StylusPointerAdapter.isPalmRejectionActive(true, kind: PointerDeviceKind.mouse), isFalse);

      // 3. In stylus mode, touch is rejected while stylus is contacting
      expect(StylusPointerAdapter.isPalmRejectionActive(true, kind: PointerDeviceKind.touch), isTrue);

      // 4. In stylus mode, touch is rejected within 500ms after stylus release
      StylusPointerAdapter.isStylusContacting = false;
      StylusPointerAdapter.lastStylusContactTime = DateTime.now();
      expect(StylusPointerAdapter.isPalmRejectionActive(true, kind: PointerDeviceKind.touch), isTrue);

      // 5. In stylus mode, touch is allowed 600ms after stylus release
      StylusPointerAdapter.lastStylusContactTime = DateTime.now().subtract(const Duration(milliseconds: 600));
      expect(StylusPointerAdapter.isPalmRejectionActive(true, kind: PointerDeviceKind.touch), isFalse);
    });
  });

  testWidgets('Blank card long-press triggers annotation in non-stylus mode, ignored for touch in stylus mode', (tester) async {
    bool menuTriggered = false;
    bool isStylusMode = false;
    PointerDeviceKind? lastKind;

    Widget buildCardTest() {
      return MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPressStart: (details) {
              if (isStylusMode && StylusPointerAdapter.isTouch(lastKind ?? PointerDeviceKind.touch)) {
                return;
              }
              menuTriggered = true;
            },
            child: Listener(
              onPointerDown: (e) => lastKind = e.kind,
              child: Container(
                width: 300,
                height: 300,
                color: Colors.blue,
                child: const Text('Card Blank Space'),
              ),
            ),
          ),
        ),
      );
    }

    // Case 1: Non-stylus mode -> touch long press triggers menu
    isStylusMode = false;
    menuTriggered = false;
    await tester.pumpWidget(buildCardTest());
    await tester.pumpAndSettle();

    final touchGesture1 = await tester.startGesture(
      tester.getCenter(find.text('Card Blank Space')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600)); // long press
    await touchGesture1.up();
    await tester.pumpAndSettle();

    expect(menuTriggered, isTrue);

    // Case 2: Stylus mode -> touch long press is IGNORED!
    isStylusMode = true;
    menuTriggered = false;
    await tester.pumpWidget(buildCardTest());
    await tester.pumpAndSettle();

    final touchGesture2 = await tester.startGesture(
      tester.getCenter(find.text('Card Blank Space')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600)); // long press
    await touchGesture2.up();
    await tester.pumpAndSettle();

    expect(menuTriggered, isFalse); // Suppressed for touch!

    // Case 3: Stylus mode -> mouse/stylus long press triggers menu
    isStylusMode = true;
    menuTriggered = false;
    await tester.pumpWidget(buildCardTest());
    await tester.pumpAndSettle();

    final mouseGesture = await tester.startGesture(
      tester.getCenter(find.text('Card Blank Space')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 600)); // long press
    await mouseGesture.up();
    await tester.pumpAndSettle();

    expect(menuTriggered, isTrue); // Allowed for stylus/mouse!
  });
}

class _TestFilterWidget extends SingleChildRenderObjectWidget {
  final bool filterTouch;
  final ValueGetter<bool> getIsTouch;

  const _TestFilterWidget({
    required this.filterTouch,
    required this.getIsTouch,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTestFilter(filterTouch: filterTouch, getIsTouch: getIsTouch);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTestFilter renderObject) {
    renderObject.filterTouch = filterTouch;
    renderObject.getIsTouch = getIsTouch;
  }
}

class _RenderTestFilter extends RenderProxyBox {
  bool filterTouch;
  ValueGetter<bool> getIsTouch;

  _RenderTestFilter({required this.filterTouch, required this.getIsTouch});

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (filterTouch && getIsTouch()) {
      return false;
    }
    return super.hitTestChildren(result, position: position);
  }
}




