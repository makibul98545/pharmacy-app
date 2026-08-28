import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:flutter/services.dart';
import '../database/app_database.dart';
import '../repositories/customer_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/medicine_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/stock_repository.dart';
import '../repositories/batch_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/supplier_ledger_entry.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:excel_plus/excel_plus.dart' as xlsx;

class ExcelAppShell extends StatefulWidget {
  final AppDatabase? database;

  const ExcelAppShell({super.key, this.database});

  @override
  State<ExcelAppShell> createState() => _ExcelAppShellState();
}

class _ExcelAppShellState extends State<ExcelAppShell> {
  late final AppDatabase _database;
  late final bool _ownsDatabase;
  String _selectedRibbon = 'Home';
  String _selectedSheet = 'Dashboard';
  String _selectedCell = 'A1';
  String? _selectionAnchor;
  String? _selectionEnd;
  bool _isDraggingSelection = false;

  void _updateSelectionFromPointer(Offset localPosition) {
    // Row header width.
    const rowHeaderWidth = 45.0;

    // Column width and row height.
    const cellWidth = 70.0;
    const cellHeight = 24.0;

    final x = localPosition.dx - rowHeaderWidth;
    final y = localPosition.dy - cellHeight; // subtract column header

    if (x < 0 || y < 0) return;

    final column = (x / cellWidth).floor() + 1;
    final row = (y / cellHeight).floor() + 1;

    if (column < 1 || row < 1 || column > 26 || row > 100) {
      return;
    }

    final address = _cellAddress(column, row);

    setState(() {
      _selectionEnd = address;
      _selectedCell = address;
    });
  }

  Future<void> _exportXlsx() async {
    if (_cells.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is no data to export.')),
      );
      return;
    }

    final workbook = xlsx.Excel.createExcel();

    final sheet = workbook['Sheet1'];

    final maxRow = _cells.keys.fold<int>(1, (max, address) {
      final row = _cellPosition(address)[1];
      return row > max ? row : max;
    });

    for (var row = 1; row <= maxRow; row++) {
      for (var column = 1; column <= 26; column++) {
        final address = _cellAddress(column, row);
        final value = _cells[address] ?? '';

        if (value.isEmpty) {
          continue;
        }

        sheet
            .cell(
              xlsx.CellIndex.indexByColumnRow(
                columnIndex: column - 1,
                rowIndex: row - 1,
              ),
            )
            .value = xlsx.TextCellValue(
          value,
        );
      }
    }

    final bytes = workbook.save();

    if (bytes == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create XLSX file.')),
      );

      return;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export XLSX',
      fileName: 'pharmacy_data.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      bytes: Uint8List.fromList(bytes),
    );

    if (!mounted) return;

    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('XLSX exported successfully.')),
      );
    }
  }

  void _showInsertMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Insert'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.view_column),
                title: const Text('Insert Column Before'),
                onTap: () {
                  Navigator.pop(context);
                  _insertColumnBefore();
                },
              ),
              ListTile(
                leading: const Icon(Icons.view_column),
                title: const Text('Insert Column After'),
                onTap: () {
                  Navigator.pop(context);
                  _insertColumnAfter();
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_rows),
                title: const Text('Insert Row Above'),
                onTap: () {
                  Navigator.pop(context);
                  _insertRowAbove();
                },
              ),

              ListTile(
                leading: const Icon(Icons.table_rows),
                title: const Text('Insert Row Below'),
                onTap: () {
                  Navigator.pop(context);
                  _insertRowBelow();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportData() async {
    final maxRow = _cells.keys.fold<int>(1, (max, address) {
      final row = _cellPosition(address)[1];
      return row > max ? row : max;
    });

    if (_cells.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is no data to export.')),
      );
      return;
    }

    final lines = <String>[];

    for (var row = 1; row <= maxRow; row++) {
      final values = <String>[];

      for (var column = 1; column <= 26; column++) {
        final address = _cellAddress(column, row);
        final value = _cells[address] ?? '';

        values.add(_escapeCsvValue(value));
      }

      lines.add(values.join(','));
    }

    final csv = lines.join('\r\n');

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Data',
      fileName: 'pharmacy_data.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );

    if (!mounted) return;

    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data exported successfully.')),
      );
    }
  }

  String _escapeCsvValue(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }

    return value;
  }

  Future<void> _importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Excel or CSV',
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );

    if (result == null) return;

    final extension = result.files.single.extension?.toLowerCase();
    final fileBytes = result.files.single.bytes;

    if (fileBytes == null || fileBytes.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected file.')),
      );

      return;
    }

    try {
      final importedCells = <String, String>{};

      if (extension == 'xlsx') {
        // =========================
        // XLSX IMPORT
        // =========================

        final workbook = xlsx.Excel.decodeBytes(fileBytes);

        if (workbook.tables.isEmpty) {
          throw Exception('The Excel file contains no worksheets.');
        }

        final sheetName = workbook.tables.keys.first;
        final sheet = workbook.tables[sheetName];

        if (sheet == null) {
          throw Exception('Could not open the first worksheet.');
        }

        for (var rowIndex = 0; rowIndex < sheet.maxRows; rowIndex++) {
          final row = sheet.rows[rowIndex];

          for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
            final cell = row[columnIndex];

            if (cell == null || cell.value == null) {
              continue;
            }

            final value = cell.value.toString();

            if (value.isEmpty) {
              continue;
            }

            final address = _cellAddress(columnIndex + 1, rowIndex + 1);

            importedCells[address] = value;
          }
        }

        if (!mounted) return;

        setState(() {
          _cells
            ..clear()
            ..addAll(importedCells);

          _selectedCell = 'A1';
          _selectionAnchor = 'A1';
          _selectionEnd = 'A1';
          _formulaController.text = '';
        });

        _gridFocusNode.requestFocus();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${importedCells.length} cells from "$sheetName".',
            ),
          ),
        );
      } else if (extension == 'csv') {
        // =========================
        // CSV IMPORT
        // =========================

        final csvText = utf8.decode(fileBytes);

        final lines = csvText.split(RegExp(r'\r?\n'));

        for (var rowIndex = 0; rowIndex < lines.length; rowIndex++) {
          final line = lines[rowIndex];

          if (line.trim().isEmpty) {
            continue;
          }

          final values = _parseCsvLine(line);

          for (
            var columnIndex = 0;
            columnIndex < values.length;
            columnIndex++
          ) {
            final value = values[columnIndex];

            if (value.isEmpty) {
              continue;
            }

            final address = _cellAddress(columnIndex + 1, rowIndex + 1);

            importedCells[address] = value;
          }
        }

        if (!mounted) return;

        setState(() {
          _cells
            ..clear()
            ..addAll(importedCells);

          _selectedCell = 'A1';
          _selectionAnchor = 'A1';
          _selectionEnd = 'A1';
          _formulaController.text = '';
        });

        _gridFocusNode.requestFocus();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${importedCells.length} cells from CSV.'),
          ),
        );
      } else {
        throw Exception('Unsupported file type.');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to import file: $e')));
    }
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();

    bool insideQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final character = line[i];

      if (character == '"') {
        if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          insideQuotes = !insideQuotes;
        }
      } else if (character == ',' && !insideQuotes) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(character);
      }
    }

    values.add(buffer.toString());

    return values;
  }

  void _insertColumnBefore() {
    final position = _cellPosition(_selectedCell);
    final column = position[0];

    _saveUndoState();

    final updated = <String, String>{};

    for (final entry in _cells.entries) {
      final cell = _cellPosition(entry.key);
      final oldColumn = cell[0];
      final row = cell[1];

      if (oldColumn >= column) {
        updated[_cellAddress(oldColumn + 1, row)] = entry.value;
      } else {
        updated[entry.key] = entry.value;
      }
    }

    setState(() {
      _cells
        ..clear()
        ..addAll(updated);

      _selectionAnchor = _cellAddress(column, position[1]);
      _selectionEnd = _selectionAnchor;
      _selectedCell = _selectionAnchor!;
    });
  }

  void _insertColumnAfter() {
    final position = _cellPosition(_selectedCell);
    final column = position[0] + 1;

    _saveUndoState();

    final updated = <String, String>{};

    for (final entry in _cells.entries) {
      final cell = _cellPosition(entry.key);
      final oldColumn = cell[0];
      final row = cell[1];

      if (oldColumn >= column) {
        updated[_cellAddress(oldColumn + 1, row)] = entry.value;
      } else {
        updated[entry.key] = entry.value;
      }
    }

    setState(() {
      _cells
        ..clear()
        ..addAll(updated);
    });
  }

  void _insertRowAbove() {
    final position = _cellPosition(_selectedCell);
    final row = position[1];

    setState(() {
      final updated = <String, String>{};

      for (final entry in _cells.entries) {
        final cell = entry.key;
        final value = entry.value;
        final cellPosition = _cellPosition(cell);
        final currentRow = cellPosition[1];

        if (currentRow >= row) {
          final newAddress = _cellAddress(cellPosition[0], currentRow + 1);
          updated[newAddress] = value;
        } else {
          updated[cell] = value;
        }
      }

      _cells
        ..clear()
        ..addAll(updated);

      _selectedCell = _cellAddress(position[0], row);
      _selectionAnchor = _selectedCell;
      _selectionEnd = _selectedCell;
    });
  }

  void _insertRowBelow() {
    final position = _cellPosition(_selectedCell);
    final row = position[1] + 1;

    setState(() {
      final updated = <String, String>{};

      for (final entry in _cells.entries) {
        final cell = entry.key;
        final value = entry.value;
        final cellPosition = _cellPosition(cell);
        final currentRow = cellPosition[1];

        if (currentRow >= row) {
          final newAddress = _cellAddress(cellPosition[0], currentRow + 1);
          updated[newAddress] = value;
        } else {
          updated[cell] = value;
        }
      }

      _cells
        ..clear()
        ..addAll(updated);

      _selectedCell = _cellAddress(position[0], position[1]);
      _selectionAnchor = _selectedCell;
      _selectionEnd = _selectedCell;
    });
  }

  void _deleteRow() {
    final position = _cellPosition(_selectedCell);
    final row = position[1];

    setState(() {
      final updated = <String, String>{};

      for (final entry in _cells.entries) {
        final cell = entry.key;
        final value = entry.value;
        final cellPosition = _cellPosition(cell);
        final currentRow = cellPosition[1];

        // Delete selected row
        if (currentRow == row) {
          continue;
        }

        // Move rows below upward
        if (currentRow > row) {
          final newAddress = _cellAddress(cellPosition[0], currentRow - 1);
          updated[newAddress] = value;
        } else {
          updated[cell] = value;
        }
      }

      _cells
        ..clear()
        ..addAll(updated);

      _selectedCell = _cellAddress(position[0], row > 1 ? row - 1 : 1);

      _selectionAnchor = _selectedCell;
      _selectionEnd = _selectedCell;
    });
  }

  void _deleteColumn() {
    final position = _cellPosition(_selectedCell);
    final column = position[0];

    _saveUndoState();

    final updated = <String, String>{};

    for (final entry in _cells.entries) {
      final cell = _cellPosition(entry.key);
      final oldColumn = cell[0];
      final row = cell[1];

      if (oldColumn == column) {
        continue;
      }

      if (oldColumn > column) {
        updated[_cellAddress(oldColumn - 1, row)] = entry.value;
      } else {
        updated[entry.key] = entry.value;
      }
    }

    setState(() {
      _cells
        ..clear()
        ..addAll(updated);

      _selectionAnchor = _selectedCell;
      _selectionEnd = _selectedCell;
    });
  }

  void _clearSelectedCells() {
    final selectedCells = _getSelectedCells();

    if (selectedCells.isEmpty) return;

    _saveUndoState();

    setState(() {
      for (final cell in selectedCells) {
        _cells.remove(cell);
      }

      _formulaController.clear();
    });
  }

  List<String> _getSelectedCells() {
    final start = _selectionAnchor ?? _selectedCell;
    final end = _selectionEnd ?? _selectedCell;

    final startColumn = _columnNumber(
      RegExp(r'[A-Z]+').firstMatch(start)!.group(0)!,
    );

    final endColumn = _columnNumber(
      RegExp(r'[A-Z]+').firstMatch(end)!.group(0)!,
    );

    final startRow = int.parse(RegExp(r'\d+').firstMatch(start)!.group(0)!);

    final endRow = int.parse(RegExp(r'\d+').firstMatch(end)!.group(0)!);

    final minColumn = startColumn < endColumn ? startColumn : endColumn;
    final maxColumn = startColumn > endColumn ? startColumn : endColumn;

    final minRow = startRow < endRow ? startRow : endRow;
    final maxRow = startRow > endRow ? startRow : endRow;

    final result = <String>[];

    for (var row = minRow; row <= maxRow; row++) {
      for (var column = minColumn; column <= maxColumn; column++) {
        result.add(_cellAddress(column, row));
      }
    }

    return result;
  }

  final List<String> _ribbonTabs = [
    'File',
    'Home',
    'Insert',
    'Page Layout',
    'Formulas',
    'Data',
    'Review',
    'View',
    'Reports',
    'Pharmacy',
  ];

  final List<String> _sheetTabs = [
    'Dashboard',
    'Sales',
    'Purchases',
    'Inventory',
    'Medicines',
    'Customers',
    'Suppliers',
    'Customer Ledger',
    'Supplier Ledger',
    'Expenses',
    'Reports',
  ];

  final List<Map<String, String>> _undoStack = [];
  final List<Map<String, String>> _redoStack = [];

  void _saveUndoState() {
    _undoStack.add(Map<String, String>.from(_cells));
    _redoStack.clear();

    // Keep memory under control.
    if (_undoStack.length > 100) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;

    _redoStack.add(Map<String, String>.from(_cells));

    setState(() {
      _cells
        ..clear()
        ..addAll(_undoStack.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;

    _undoStack.add(Map<String, String>.from(_cells));

    setState(() {
      _cells
        ..clear()
        ..addAll(_redoStack.removeLast());
    });
  }

  Future<List<SupplierLedgerEntry>>? _supplierLedgerFuture;

  void _loadSupplierLedger() {
    if (_suppliers.isEmpty) {
      setState(() {
        _supplierLedgerFuture = Future.value([]);
      });
      return;
    }

    final supplier = _suppliers.first;

    setState(() {
      _supplierLedgerFuture = supplierRepository.getLedger(supplier.id);
    });
  }

  List<int> _cellPosition(String address) {
    final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(address);

    if (match == null) {
      return [1, 1];
    }

    return [_columnNumber(match.group(1)!), int.parse(match.group(2)!)];
  }

  String _cellAddress(int column, int row) {
    return '${_columnName(column - 1)}$row';
  }

  List<String> _selectedRangeCells() {
    final anchor = _selectionAnchor;
    final end = _selectionEnd;

    if (anchor == null || end == null) {
      return [_selectedCell];
    }

    final start = _cellPosition(anchor);
    final finish = _cellPosition(end);

    final minColumn = start[0] < finish[0] ? start[0] : finish[0];

    final maxColumn = start[0] > finish[0] ? start[0] : finish[0];

    final minRow = start[1] < finish[1] ? start[1] : finish[1];

    final maxRow = start[1] > finish[1] ? start[1] : finish[1];

    final cells = <String>[];

    for (var row = minRow; row <= maxRow; row++) {
      for (var column = minColumn; column <= maxColumn; column++) {
        cells.add(_cellAddress(column, row));
      }
    }

    return cells;
  }

  final Map<String, String> _cells = {};
  Set<int> _hiddenRows = {};
  final Map<String, List<String>> _cellValidations = {};

  bool _freezeTopRow = false;
  bool _freezeFirstColumn = false;
  bool _syncingFrozenScroll = false;
  bool _splitView = false;
  int? _splitRow;
  int? _splitColumn;
  double _zoom = 1.0;

  final ScrollController _horizontalScrollController = ScrollController();

  final ScrollController _headerHorizontalScrollController = ScrollController();

  final ScrollController _verticalScrollController = ScrollController();

  final ScrollController _frozenVerticalScrollController = ScrollController();

  // Split pane scroll controllers
  final ScrollController _splitTopLeftVerticalController = ScrollController();

  final ScrollController _splitTopRightVerticalController = ScrollController();

  final ScrollController _splitTopRightHorizontalController =
      ScrollController();

  final ScrollController _splitBottomLeftHorizontalController =
      ScrollController();

  final ScrollController _splitBottomRightVerticalController =
      ScrollController();

  final ScrollController _splitBottomRightHorizontalController =
      ScrollController();

  final ScrollController _splitTopLeftHorizontalController = ScrollController();

  final ScrollController _splitBottomLeftVerticalController =
      ScrollController();

  final FocusNode _gridFocusNode = FocusNode();
  final FocusNode _cellEditFocusNode = FocusNode();
  late final TextEditingController _formulaController;
  final FocusNode _formulaFocusNode = FocusNode();

  String? _editingCell;
  late final TextEditingController _cellEditController;

  // Sales sheet state
  List<Medicine> _salesMedicines = [];
  List<Customer> _salesCustomers = [];
  List<Batch> _salesBatches = [];
  List<InventoryItem> _inventoryItems = [];

  String? _salesCustomerId;
  String? _salesMedicineId;
  String? _salesBatchId;

  int _salesQty = 1;
  double _salesRate = 0.0;
  double _salesGst = 0.0;
  double _salesDiscount = 0.0;
  double _salesPaid = 0.0;

  late final TextEditingController _salesInvoiceController;
  late final TextEditingController _salesQtyController;
  late final TextEditingController _salesRateController;
  late final TextEditingController _salesDiscountController;
  late final TextEditingController _salesPaidController;

  // Purchase sheet state
  List<Supplier> _purchaseSuppliers = [];
  List<Medicine> _purchaseMedicines = [];
  String? _purchaseSupplierId;
  String? _purchaseMedicineId;
  late final TextEditingController _purchaseInvoiceController;
  late final TextEditingController _purchaseBatchController;
  late final TextEditingController _purchaseDateController;
  late final TextEditingController _purchaseQtyController;
  late final TextEditingController _purchaseRateController;
  late final TextEditingController _purchaseMrpController;
  late final TextEditingController _purchaseGstController;
  int _purchaseQty = 1;
  double _purchaseRate = 0.0;
  double _purchaseMrp = 0.0;
  double _purchaseGst = 0.0;

  // Suppliers sheet state
  List<Supplier> _suppliers = [];
  final Map<String, double> _supplierDues = {};
  String _supplierSearch = '';
  late final TextEditingController _supplierSearchController;

  late final PurchaseRepository purchaseRepository;
  late final SupplierRepository supplierRepository;

  KeyEventResult _handleGridKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (_editingCell == null &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      _clearSelectedCells();

      return KeyEventResult.handled;
    }

    // Excel keyboard shortcuts
    final hardwareKeyboard = HardwareKeyboard.instance;

    if (hardwareKeyboard.isControlPressed) {
      if (key == LogicalKeyboardKey.keyC) {
        _copySelectedCell();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyX) {
        _cutSelectedCell();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyV) {
        _pasteIntoSelectedCell();
        return KeyEventResult.handled;
      }
    }

    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        _undo();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyY) {
        _redo();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyC) {
        _copySelectedCell();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyX) {
        _cutSelectedCell();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyV) {
        _pasteIntoSelectedCell();
        return KeyEventResult.handled;
      }
    }

    // Editing mode.
    if (_editingCell != null) {
      if (key == LogicalKeyboardKey.escape) {
        _cancelCellEdit();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.enter) {
        _commitCellEdit();
        _moveSelection(rowDelta: 1);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.tab) {
        _commitCellEdit();
        _moveSelection(
          columnDelta: HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
        );
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    // Start editing when the user types.
    final character = event.character;

    if (character != null &&
        character.isNotEmpty &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _startCellEditing(initialText: character);
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      var column = _cellPosition(_selectedCell)[0];
      var row = _cellPosition(_selectedCell)[1];

      if (key == LogicalKeyboardKey.arrowRight) {
        column++;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        column = column > 1 ? column - 1 : 1;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        row++;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        row = row > 1 ? row - 1 : 1;
      } else {
        // Not a range-selection key.
        return KeyEventResult.ignored;
      }

      setState(() {
        _selectionAnchor ??= _selectedCell;
        _selectionEnd = _cellAddress(column, row);
        _selectedCell = _selectionEnd!;
      });

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(columnDelta: 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(columnDelta: -1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(rowDelta: 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(rowDelta: -1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.tab) {
      _moveSelection(
        columnDelta: HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      _moveSelection(
        rowDelta: HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_cells.containsKey(_selectedCell)) {
        _saveUndoState();

        setState(() {
          _cells.remove(_selectedCell);
        });
      }

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.f2) {
      _startCellEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copySelectedCell() async {
    final cells = _selectedRangeCells();

    if (cells.isEmpty) return;

    final positions = cells.map(_cellPosition).toList();

    final minColumn = positions
        .map((p) => p[0])
        .reduce((a, b) => a < b ? a : b);

    final maxColumn = positions
        .map((p) => p[0])
        .reduce((a, b) => a > b ? a : b);

    final minRow = positions.map((p) => p[1]).reduce((a, b) => a < b ? a : b);

    final maxRow = positions.map((p) => p[1]).reduce((a, b) => a > b ? a : b);

    final lines = <String>[];

    for (var row = minRow; row <= maxRow; row++) {
      final values = <String>[];

      for (var column = minColumn; column <= maxColumn; column++) {
        final address = _cellAddress(column, row);
        values.add(_cells[address] ?? '');
      }

      lines.add(values.join('\t'));
    }

    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
  }

  Future<void> _cutSelectedCell() async {
    await _copySelectedCell();

    final selectedCells = List<String>.from(_selectedRangeCells());

    setState(() {
      for (final cell in selectedCells) {
        _cells.remove(cell);
      }
    });
  }

  Future<void> _pasteIntoSelectedCell() async {
    final data = await Clipboard.getData('text/plain');

    if (data == null || data.text == null) return;

    final text = data.text!;

    if (text.isEmpty) return;

    final rows = text.split('\n');

    final start = _cellPosition(_selectedCell);
    final startColumn = start[0];
    final startRow = start[1];

    setState(() {
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final columns = rows[rowIndex].split('\t');

        for (var columnIndex = 0; columnIndex < columns.length; columnIndex++) {
          final address = _cellAddress(
            startColumn + columnIndex,
            startRow + rowIndex,
          );

          final value = columns[columnIndex];

          if (value.isEmpty) {
            _cells.remove(address);
          } else {
            _cells[address] = value;
          }
        }
      }

      _selectionAnchor = _selectedCell;
      _selectionEnd = _selectedCell;
    });

    _recalculateSalesRowIfNeeded(_selectedCell);
  }

  late final MedicineRepository medicineRepository;
  late final CustomerRepository customerRepository;
  late final SaleRepository saleRepository;
  late final StockRepository stockRepository;
  late final BatchRepository batchRepository;
  late final InventoryRepository inventoryRepository;

  void _moveSelection({int rowDelta = 0, int columnDelta = 0}) {
    final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(_selectedCell);

    if (match == null) {
      return;
    }

    var column = _columnNumber(match.group(1)!);
    var row = int.parse(match.group(2)!);

    column += columnDelta;
    row += rowDelta;

    if (column < 1) {
      column = 1;
    }

    if (row < 1) {
      row = 1;
    }

    final newCell = '${_columnName(column - 1)}$row';

    setState(() {
      _selectedCell = newCell;
      _selectionAnchor = newCell;
      _selectionEnd = newCell;
    });
  }

  void _syncFrozenVerticalScroll() {
    _verticalScrollController.addListener(() {
      if (_syncingFrozenScroll) return;

      if (!_frozenVerticalScrollController.hasClients) return;

      _syncingFrozenScroll = true;

      final offset = _verticalScrollController.offset.clamp(
        0.0,
        _frozenVerticalScrollController.position.maxScrollExtent,
      );

      _frozenVerticalScrollController.jumpTo(offset);

      _syncingFrozenScroll = false;
    });

    _frozenVerticalScrollController.addListener(() {
      if (_syncingFrozenScroll) return;

      if (!_verticalScrollController.hasClients) return;

      _syncingFrozenScroll = true;

      final offset = _frozenVerticalScrollController.offset.clamp(
        0.0,
        _verticalScrollController.position.maxScrollExtent,
      );

      _verticalScrollController.jumpTo(offset);

      _syncingFrozenScroll = false;
    });
  }

  Widget _buildSalesSheet() {
    Medicine? selectedMedicine;
    for (final medicine in _salesMedicines) {
      if (medicine.id == _salesMedicineId) {
        selectedMedicine = medicine;
        break;
      }
    }

    final filteredBatches = _salesMedicineId == null
        ? <Batch>[]
        : _salesBatches
              .where((batch) => batch.medicineId == _salesMedicineId)
              .toList();

    Batch? selectedBatch;
    for (final batch in filteredBatches) {
      if (batch.id == _salesBatchId) {
        selectedBatch = batch;
        break;
      }
    }

    final availableStock = selectedBatch == null
        ? 0
        : _salesStockForBatch[selectedBatch.id] ?? 0;

    final total = _calculateSalesTotal();
    final due = total - _salesPaid;

    return Container(
      color: const Color(0xfff3f3f3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xffd0d0d0))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.point_of_sale,
                  size: 20,
                  color: Color(0xff217346),
                ),
                const SizedBox(width: 8),
                const Text(
                  'New Sale',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  availableStock > 0
                      ? 'Available stock: $availableStock'
                      : 'Select a batch',
                  style: TextStyle(
                    fontSize: 12,
                    color: availableStock > 0
                        ? const Color(0xff217346)
                        : const Color(0xff777777),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _salesField(
                          label: 'Invoice No',
                          controller: _salesInvoiceController,
                          hint: 'Auto generated if blank',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _salesInfoField(
                          label: 'Date',
                          value: _formatSalesDate(DateTime.now()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: _salesCustomerId,
                          isExpanded: true,
                          decoration: _salesDecoration('Customer'),
                          hint: const Text('Walk-in / select customer'),
                          items: _salesCustomers
                              .map(
                                (customer) => DropdownMenuItem<String>(
                                  value: customer.id,
                                  child: Text(
                                    customer.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _salesCustomerId = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xffd0d0d0)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 34,
                        dataRowMinHeight: 54,
                        dataRowMaxHeight: 64,
                        columnSpacing: 12,
                        headingTextStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff333333),
                        ),
                        columns: const [
                          DataColumn(label: Text('Medicine')),
                          DataColumn(label: Text('Batch')),
                          DataColumn(label: Text('Stock')),
                          DataColumn(label: Text('Qty')),
                          DataColumn(label: Text('Rate')),
                          DataColumn(label: Text('GST %')),
                          DataColumn(label: Text('Discount')),
                          DataColumn(label: Text('Total')),
                        ],
                        rows: [
                          DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 190,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _salesMedicineId,
                                    isExpanded: true,
                                    decoration: _salesDecoration('Medicine'),
                                    hint: const Text('Select medicine'),
                                    items: _salesMedicines
                                        .map(
                                          (medicine) =>
                                              DropdownMenuItem<String>(
                                                value: medicine.id,
                                                child: Text(
                                                  medicine.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      Medicine? medicine;
                                      for (final item in _salesMedicines) {
                                        if (item.id == value) {
                                          medicine = item;
                                          break;
                                        }
                                      }
                                      setState(() {
                                        _salesMedicineId = value;
                                        _salesBatchId = null;
                                        _salesGst = medicine?.gstPercent ?? 0.0;
                                        _salesRate = 0.0;
                                        _salesRateController.clear();
                                      });
                                    },
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 150,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _salesBatchId,
                                    isExpanded: true,
                                    decoration: _salesDecoration('Batch'),
                                    hint: const Text('Select batch'),
                                    items: filteredBatches
                                        .map(
                                          (batch) => DropdownMenuItem<String>(
                                            value: batch.id,
                                            child: Text(
                                              '${batch.batchNo} • MRP ₹${batch.mrp.toStringAsFixed(2)}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) async {
                                      if (value == null) return;
                                      Batch? batch;
                                      for (final item in filteredBatches) {
                                        if (item.id == value) {
                                          batch = item;
                                          break;
                                        }
                                      }
                                      if (batch == null) {
                                        _showSalesMessage(
                                          'Selected batch is no longer available.',
                                        );
                                        return;
                                      }

                                      final stock = await stockRepository
                                          .getBatchStock(batch.id);

                                      if (!mounted) return;

                                      setState(() {
                                        _salesBatchId = value;
                                        _salesRate = batch!.mrp;
                                        _salesRateController.text = batch.mrp
                                            .toStringAsFixed(2);
                                        _salesStockForBatch[batch.id] = stock;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 55,
                                  child: Center(child: Text('$availableStock')),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 75,
                                  child: _salesNumberField(
                                    controller: _salesQtyController,
                                    onChanged: (value) {
                                      _salesQty = int.tryParse(value) ?? 0;
                                      setState(() {});
                                    },
                                    decimal: false,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 95,
                                  child: _salesNumberField(
                                    controller: _salesRateController,
                                    onChanged: (value) {
                                      _salesRate =
                                          double.tryParse(value) ?? 0.0;
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 70,
                                  child: _salesInfoField(
                                    label: 'GST',
                                    value: '${_salesGst.toStringAsFixed(2)}%',
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 95,
                                  child: _salesNumberField(
                                    controller: _salesDiscountController,
                                    onChanged: (value) {
                                      _salesDiscount =
                                          double.tryParse(value) ?? 0.0;
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 105,
                                  child: Text(
                                    '₹${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _salesSummaryCard(
                          'Subtotal',
                          '₹${(_salesQty * _salesRate).toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _salesSummaryCard(
                          'GST',
                          '₹${((_salesQty * _salesRate) * _salesGst / 100).toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _salesSummaryCard(
                          'Total',
                          '₹${total.toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _salesNumberField(
                          controller: _salesPaidController,
                          label: 'Paid',
                          onChanged: (value) {
                            _salesPaid = double.tryParse(value) ?? 0.0;
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _salesSummaryCard(
                          'Due',
                          '₹${due.toStringAsFixed(2)}',
                          emphasis: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _clearSalesForm,
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text('Clear'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _saveSale,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save Sale'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff217346),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (selectedMedicine != null || selectedBatch == null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xffd0d0d0)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Color(0xff217346),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedBatch == null
                                  ? '${selectedMedicine?.name ?? ''} • Select a batch to continue.'
                                  : '${selectedMedicine?.name ?? ''} • Batch ${selectedBatch.batchNo} • MRP ₹${selectedBatch.mrp.toStringAsFixed(2)} • Stock $availableStock',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  final Map<String, int> _salesStockForBatch = {};

  InputDecoration _purchaseDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _purchaseNumberField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? label,
    bool decimal = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textAlign: TextAlign.right,
      decoration: _purchaseDecoration(label ?? ''),
      onChanged: onChanged,
    );
  }

  double _calculatePurchaseTotal() {
    final subtotal = _purchaseQty * _purchaseRate;
    return subtotal + (subtotal * _purchaseGst / 100);
  }

  Widget _buildPurchasesSheet() {
    final total = _calculatePurchaseTotal();

    return Container(
      color: const Color(0xfff3f3f3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: const Row(
              children: [
                Icon(Icons.shopping_cart, size: 20, color: Color(0xff217346)),
                SizedBox(width: 8),
                Text(
                  'New Purchase',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _purchaseInvoiceController,
                          decoration: _purchaseDecoration(
                            'Invoice No',
                          ).copyWith(hintText: 'Auto generated if blank'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _purchaseDateController,
                          decoration: _purchaseDecoration('Purchase Date'),
                          readOnly: true,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              _purchaseDateController.text = _formatSalesDate(
                                picked,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _purchaseSupplierId,
                          isExpanded: true,
                          decoration: _purchaseDecoration('Supplier'),
                          hint: const Text('Select supplier'),
                          items: _purchaseSuppliers
                              .map(
                                (supplier) => DropdownMenuItem<String>(
                                  value: supplier.id,
                                  child: Text(
                                    supplier.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _purchaseSupplierId = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xffd0d0d0)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: const [
                            Expanded(child: Text('Medicine')),
                            Expanded(child: Text('Batch No')),
                            SizedBox(width: 90, child: Text('Qty')),
                            SizedBox(width: 120, child: Text('Purchase Rate')),
                            SizedBox(width: 120, child: Text('MRP')),
                            SizedBox(width: 100, child: Text('GST %')),
                            SizedBox(width: 120, child: Text('Total')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _purchaseMedicineId,
                                isExpanded: true,
                                decoration: _purchaseDecoration('Medicine'),
                                hint: const Text('Select medicine'),
                                items: _purchaseMedicines
                                    .map(
                                      (medicine) => DropdownMenuItem<String>(
                                        value: medicine.id,
                                        child: Text(
                                          medicine.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  Medicine? medicine;
                                  for (final item in _purchaseMedicines) {
                                    if (item.id == value) {
                                      medicine = item;
                                      break;
                                    }
                                  }
                                  setState(() {
                                    _purchaseMedicineId = value;
                                    _purchaseGst = medicine?.gstPercent ?? 0.0;
                                    _purchaseGstController.text = _purchaseGst
                                        .toStringAsFixed(2);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _purchaseBatchController,
                                decoration: _purchaseDecoration('Batch No'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: _purchaseNumberField(
                                controller: _purchaseQtyController,
                                decimal: false,
                                onChanged: (v) => setState(
                                  () => _purchaseQty = int.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: _purchaseNumberField(
                                controller: _purchaseRateController,
                                onChanged: (v) => setState(
                                  () => _purchaseRate = double.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: _purchaseNumberField(
                                controller: _purchaseMrpController,
                                onChanged: (v) => setState(
                                  () => _purchaseMrp = double.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: _purchaseNumberField(
                                controller: _purchaseGstController,
                                onChanged: (v) => setState(
                                  () => _purchaseGst = double.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  '₹${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _clearPurchaseForm,
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text('Clear'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _savePurchase,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save Purchase'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff217346),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _zoomIn() {
    setState(() {
      _zoom = (_zoom + 0.1).clamp(0.5, 2.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - 0.1).clamp(0.5, 2.0);
    });
  }

  void _setZoom(double value) {
    setState(() {
      _zoom = value.clamp(0.5, 2.0);
    });
  }

  void _toggleFreezeTopRow() {
    setState(() {
      _freezeTopRow = !_freezeTopRow;
    });
  }

  void _toggleFreezeFirstColumn() {
    setState(() {
      _freezeFirstColumn = !_freezeFirstColumn;
    });
  }

  void _toggleFreezePanes() {
    setState(() {
      final shouldFreeze = !(_freezeTopRow && _freezeFirstColumn);

      _freezeTopRow = shouldFreeze;
      _freezeFirstColumn = shouldFreeze;
    });
  }

  void _clearPurchaseForm() {
    setState(() {
      _purchaseSupplierId = null;
      _purchaseMedicineId = null;
      _purchaseInvoiceController.clear();
      _purchaseBatchController.clear();
      _purchaseQtyController.text = '1';
      _purchaseRateController.clear();
      _purchaseMrpController.clear();
      _purchaseGstController.text = '0';
      _purchaseQty = 1;
      _purchaseRate = 0;
      _purchaseMrp = 0;
      _purchaseGst = 0;
    });
  }

  Future<void> _savePurchase() async {
    if (_purchaseSupplierId == null) {
      _showSalesMessage('Select a supplier first.');
      return;
    }
    if (_purchaseMedicineId == null) {
      _showSalesMessage('Select a medicine first.');
      return;
    }
    final batchNo = _purchaseBatchController.text.trim();
    if (batchNo.isEmpty) {
      _showSalesMessage('Enter a batch number.');
      return;
    }
    if (_purchaseQty <= 0) {
      _showSalesMessage('Quantity must be greater than zero.');
      return;
    }
    if (_purchaseRate < 0 || _purchaseMrp < 0 || _purchaseGst < 0) {
      _showSalesMessage('Rate, MRP and GST cannot be negative.');
      return;
    }

    final now = DateTime.now();
    final purchaseId = 'purchase-${now.microsecondsSinceEpoch}';
    final invoiceNo = _purchaseInvoiceController.text.trim().isEmpty
        ? 'PUR-${now.millisecondsSinceEpoch}'
        : _purchaseInvoiceController.text.trim();

    try {
      Batch? existingBatch;
      final batches = await batchRepository.getByMedicineId(
        _purchaseMedicineId!,
      );
      for (final batch in batches) {
        if (batch.batchNo.trim().toLowerCase() == batchNo.toLowerCase()) {
          existingBatch = batch;
          break;
        }
      }

      final batchId =
          existingBatch?.id ?? 'batch-${now.microsecondsSinceEpoch}';
      if (existingBatch == null) {
        await batchRepository.insertBatch(
          id: batchId,
          medicineId: _purchaseMedicineId!,
          supplierId: _purchaseSupplierId,
          batchNo: batchNo,
          expiryDate: now.add(const Duration(days: 365)),
          purchaseRate: _purchaseRate,
          mrp: _purchaseMrp,
        );
      }

      await purchaseRepository.createPurchase(
        purchaseId: purchaseId,
        invoiceNo: invoiceNo,
        supplierId: _purchaseSupplierId!,
        purchaseDate: now,
        items: [
          PurchaseItemData(
            id: '$purchaseId-item-1',
            medicineId: _purchaseMedicineId!,
            batchId: batchId,
            quantity: _purchaseQty,
            purchaseRate: _purchaseRate,
            mrp: _purchaseMrp,
            gstPercent: _purchaseGst,
          ),
        ],
      );

      await _loadSalesData();
      await _loadPurchaseData();
      await _loadInventoryData();
      if (!mounted) return;
      _showSalesMessage(
        'Purchase $invoiceNo saved successfully. Total ₹${_calculatePurchaseTotal().toStringAsFixed(2)}.',
      );
      _clearPurchaseForm();
    } catch (error) {
      _showSalesMessage('Purchase could not be saved: $error');
    }
  }

  InputDecoration _salesDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    );
  }

  Widget _salesField({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      decoration: _salesDecoration(label).copyWith(hintText: hint),
      style: const TextStyle(fontSize: 12),
    );
  }

  Widget _salesNumberField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? label,
    bool decimal = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textAlign: TextAlign.right,
      decoration: _salesDecoration(label ?? '').copyWith(labelText: label),
      style: const TextStyle(fontSize: 12),
      onChanged: onChanged,
    );
  }

  Widget _salesInfoField({required String label, required String value}) {
    return InputDecorator(
      decoration: _salesDecoration(label),
      child: Text(
        value,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _salesSummaryCard(
    String label,
    String value, {
    bool emphasis = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: emphasis ? const Color(0xff217346) : const Color(0xffd0d0d0),
          width: emphasis ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xff666666)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: emphasis
                  ? const Color(0xff217346)
                  : const Color(0xff222222),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateSalesTotal() {
    final subtotal = _salesQty * _salesRate;
    final gst = subtotal * _salesGst / 100;
    return subtotal + gst - _salesDiscount;
  }

  String _formatSalesDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day-$month-${date.year}';
  }

  void _clearSalesForm() {
    setState(() {
      _salesCustomerId = null;
      _salesMedicineId = null;
      _salesBatchId = null;
      _salesQty = 1;
      _salesRate = 0.0;
      _salesGst = 0.0;
      _salesDiscount = 0.0;
      _salesPaid = 0.0;
      _salesInvoiceController.clear();
      _salesQtyController.text = '1';
      _salesRateController.clear();
      _salesDiscountController.text = '0';
      _salesPaidController.text = '0';
    });
  }

  Future<void> _saveSale() async {
    if (_salesMedicineId == null) {
      _showSalesMessage('Select a medicine first.');
      return;
    }
    if (_salesBatchId == null) {
      _showSalesMessage('Select a batch first.');
      return;
    }
    if (_salesQty <= 0) {
      _showSalesMessage('Quantity must be greater than zero.');
      return;
    }
    if (_salesRate < 0) {
      _showSalesMessage('Rate cannot be negative.');
      return;
    }
    if (_salesDiscount < 0 || _salesPaid < 0) {
      _showSalesMessage('Discount and paid amount cannot be negative.');
      return;
    }

    Batch? batch;
    for (final item in _salesBatches) {
      if (item.id == _salesBatchId) {
        batch = item;
        break;
      }
    }
    if (batch == null) {
      _showSalesMessage('Selected batch is no longer available.');
      return;
    }
    final availableStock = await stockRepository.getBatchStock(batch.id);

    if (_salesQty > availableStock) {
      _showSalesMessage(
        'Insufficient stock. Available: $availableStock, requested: $_salesQty.',
      );
      return;
    }

    final total = _calculateSalesTotal();
    if (total < 0) {
      _showSalesMessage('Discount cannot make the invoice total negative.');
      return;
    }
    if (_salesPaid > total) {
      _showSalesMessage('Paid amount cannot exceed the invoice total.');
      return;
    }

    final now = DateTime.now();
    final saleId = 'sale-${now.microsecondsSinceEpoch}';
    final invoiceNo = _salesInvoiceController.text.trim().isEmpty
        ? 'SALE-${now.millisecondsSinceEpoch}'
        : _salesInvoiceController.text.trim();

    try {
      await saleRepository.createSale(
        saleId: saleId,
        invoiceNo: invoiceNo,
        customerId: _salesCustomerId,
        saleDate: now,
        items: [
          SaleItemData(
            id: '$saleId-item-1',
            medicineId: _salesMedicineId!,
            batchId: _salesBatchId!,
            quantity: _salesQty,
            saleRate: _salesRate,
            mrp: batch.mrp,
            gstPercent: _salesGst,
            discountAmount: _salesDiscount,
          ),
        ],
        paidAmount: _salesPaid,
      );

      final remainingStock = await stockRepository.getBatchStock(batch.id);
      if (mounted) {
        setState(() {
          _salesStockForBatch[batch!.id] = remainingStock;
        });
      }

      await _loadInventoryData();

      if (!mounted) return;
      _showSalesMessage(
        'Sale $invoiceNo saved successfully. Total ₹${total.toStringAsFixed(2)}, due ₹${(total - _salesPaid).toStringAsFixed(2)}.',
      );
      _clearSalesForm();
    } catch (error) {
      _showSalesMessage('Sale could not be saved: $error');
    }
  }

  void _showSalesMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3f3f3),
      body: SafeArea(
        child: Column(
          children: [
            _buildTitleBar(),
            _buildRibbonTabs(),
            _buildRibbon(),
            _buildFormulaBar(),
            Expanded(child: _buildWorksheet()),
            _buildSheetTabs(),
            _buildStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 34,
      color: const Color(0xff217346),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.grid_on, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            'MM LifeCare Pharmacy',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Minimize',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
            onPressed: () {},
            icon: const Icon(Icons.remove, size: 16, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Maximize',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
            onPressed: () {},
            icon: const Icon(Icons.crop_square, size: 15, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
            onPressed: () {},
            icon: const Icon(Icons.close, size: 17, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonTabs() {
    return Container(
      height: 38,
      color: const Color(0xff217346),
      child: Row(
        children: [
          _quickButton(Icons.save_outlined, 'Save'),
          _quickButton(Icons.undo, 'Undo', onPressed: _undo),
          _quickButton(Icons.redo, 'Redo', onPressed: _redo),
          const SizedBox(width: 8),
          ..._ribbonTabs.map((tab) {
            final selected = _selectedRibbon == tab;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedRibbon = tab;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),

                child: Text(
                  tab,
                  style: TextStyle(
                    color: selected ? const Color(0xff217346) : Colors.white,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _quickButton(
    IconData icon,
    String tooltip, {
    VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
      icon: Icon(icon, size: 17, color: Colors.white),
    );
  }

  Widget _buildRibbon() {
    if (_selectedRibbon == 'File') {
      return _buildFileRibbon();
    }

    if (_selectedRibbon == 'Insert') {
      return _buildInsertRibbon();
    }

    if (_selectedRibbon == 'Data') {
      return _buildDataRibbon();
    }

    if (_selectedRibbon == 'View') {
      return _buildViewRibbon();
    }

    if (_selectedRibbon == 'Reports') {
      return _buildReportsRibbon();
    }

    if (_selectedRibbon == 'Pharmacy') {
      return _buildPharmacyRibbon();
    }

    return _buildHomeRibbon();
  }

  Widget _ribbonContainer(List<Widget> children) {
    return Container(
      height: 94,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffd0d0d0))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _ribbonGroup(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xffdddddd))),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Color(0xff555555)),
          ),
        ],
      ),
    );
  }

  Widget _ribbonButton(IconData icon, String label, {VoidCallback? onTap}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 62,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 23, color: const Color(0xff333333)),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSplit() {
    if (_splitView) {
      setState(() {
        _splitView = false;
        _splitRow = null;
        _splitColumn = null;
      });

      return;
    }

    final position = _cellPosition(_selectedCell);

    final splitRow = position[1];
    final splitColumn = position[0];

    setState(() {
      _splitRow = splitRow;
      _splitColumn = splitColumn;
      _splitView = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_splitView) return;

      const rowHeight = 24.0;
      const columnWidth = 70.0;
      const rowHeaderWidth = 45.0;

      final horizontalOffset = rowHeaderWidth + (splitColumn * columnWidth);

      final verticalOffset = splitRow * rowHeight;

      // ==========================================================
      // TOP-LEFT
      // ==========================================================

      if (_splitTopLeftHorizontalController.hasClients) {
        _splitTopLeftHorizontalController.jumpTo(0);
      }

      if (_splitTopLeftVerticalController.hasClients) {
        _splitTopLeftVerticalController.jumpTo(0);
      }

      // ==========================================================
      // TOP-RIGHT
      // ==========================================================

      if (_splitTopRightHorizontalController.hasClients) {
        final max = _splitTopRightHorizontalController.position.maxScrollExtent;

        _splitTopRightHorizontalController.jumpTo(
          horizontalOffset.clamp(0.0, max),
        );
      }

      if (_splitTopRightVerticalController.hasClients) {
        _splitTopRightVerticalController.jumpTo(0);
      }

      // ==========================================================
      // BOTTOM-LEFT
      // ==========================================================

      if (_splitBottomLeftHorizontalController.hasClients) {
        _splitBottomLeftHorizontalController.jumpTo(0);
      }

      if (_splitBottomLeftVerticalController.hasClients) {
        final max = _splitBottomLeftVerticalController.position.maxScrollExtent;

        _splitBottomLeftVerticalController.jumpTo(
          verticalOffset.clamp(0.0, max),
        );
      }

      // ==========================================================
      // BOTTOM-RIGHT
      // ==========================================================

      if (_splitBottomRightHorizontalController.hasClients) {
        final max =
            _splitBottomRightHorizontalController.position.maxScrollExtent;

        _splitBottomRightHorizontalController.jumpTo(
          horizontalOffset.clamp(0.0, max),
        );
      }

      if (_splitBottomRightVerticalController.hasClients) {
        final max =
            _splitBottomRightVerticalController.position.maxScrollExtent;

        _splitBottomRightVerticalController.jumpTo(
          verticalOffset.clamp(0.0, max),
        );
      }
    });
  }

  Widget _buildHomeRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Clipboard', [
        _ribbonButton(Icons.content_paste, 'Paste'),
        _ribbonButton(Icons.content_cut, 'Cut'),
        _ribbonButton(Icons.copy, 'Copy'),
      ]),
      _ribbonGroup('Font', [
        _ribbonButton(Icons.format_bold, 'Bold'),
        _ribbonButton(Icons.format_italic, 'Italic'),
        _ribbonButton(Icons.format_underlined, 'Underline'),
        _ribbonButton(Icons.format_color_fill, 'Fill'),
        _ribbonButton(Icons.format_color_text, 'Font Color'),
      ]),
      _ribbonGroup('Alignment', [
        _ribbonButton(Icons.format_align_left, 'Left'),
        _ribbonButton(Icons.format_align_center, 'Center'),
        _ribbonButton(Icons.format_align_right, 'Right'),
        _ribbonButton(Icons.wrap_text, 'Wrap Text'),
      ]),
      _ribbonGroup('Number', [
        _ribbonButton(Icons.currency_rupee, 'Currency'),
        _ribbonButton(Icons.percent, 'Percent'),
        _ribbonButton(Icons.calendar_month, 'Date'),
      ]),
      _ribbonGroup('Styles', [
        _ribbonButton(Icons.format_color_fill, 'Conditional Formatting'),
        _ribbonButton(Icons.table_chart, 'Format as Table'),
      ]),
      _ribbonGroup('Cells', [
        _ribbonButton(Icons.add_box_outlined, 'Insert', onTap: _showInsertMenu),
        _ribbonButton(Icons.delete_outline, 'Delete Row', onTap: _deleteRow),
        _ribbonButton(
          Icons.view_column_outlined,
          'Delete Column',
          onTap: _deleteColumn,
        ),
        _ribbonButton(Icons.format_size, 'Format'),
      ]),
      _ribbonGroup('Editing', [
        _ribbonButton(Icons.search, 'Find', onTap: _showFindDialog),
        _ribbonButton(Icons.undo, 'Undo', onTap: _undo),
        _ribbonButton(Icons.redo, 'Redo', onTap: _redo),
      ]),
    ]);
  }

  Widget _buildFileRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Workbook', [
        _ribbonButton(Icons.note_add, 'New'),
        _ribbonButton(Icons.folder_open, 'Open'),
        _ribbonButton(Icons.save, 'Save'),
      ]),
      _ribbonGroup('Import / Export', [
        _ribbonButton(Icons.upload_file, 'Import Data', onTap: _importData),
        _ribbonButton(Icons.download, 'Export XLSX', onTap: _exportXlsx),
        _ribbonButton(Icons.table_view, 'Export CSV', onTap: _exportData),
        _ribbonButton(Icons.sync, 'Refresh'),
      ]),
      _ribbonGroup('Export', [
        _ribbonButton(Icons.download, 'Excel'),
        _ribbonButton(Icons.picture_as_pdf, 'PDF'),
        _ribbonButton(Icons.print, 'Print'),
      ]),
    ]);
  }

  Widget _buildInsertRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Tables', [
        _ribbonButton(Icons.table_chart, 'Table'),
        _ribbonButton(Icons.pivot_table_chart, 'Pivot Table'),
      ]),
      _ribbonGroup('Charts', [
        _ribbonButton(Icons.bar_chart, 'Column'),
        _ribbonButton(Icons.show_chart, 'Line'),
        _ribbonButton(Icons.pie_chart, 'Pie'),
      ]),
      _ribbonGroup('Objects', [
        _ribbonButton(Icons.image, 'Image'),
        _ribbonButton(Icons.link, 'Link'),
      ]),
    ]);
  }

  Widget _buildDataRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Sort & Filter', [
        _ribbonButton(Icons.sort, 'Sort', onTap: _showSortDialog),
        _ribbonButton(Icons.filter_alt, 'Filter', onTap: _showFilterDialog),
        _ribbonButton(Icons.filter_alt_off, 'Clear', onTap: _clearFilter),
      ]),

      _ribbonGroup('Data Tools', [
        _ribbonButton(Icons.rule, 'Validation', onTap: _showValidationDialog),
        _ribbonButton(
          Icons.cleaning_services,
          'Remove Duplicates',
          onTap: _removeDuplicates,
        ),
      ]),

      _ribbonGroup('Import / Export', [
        _ribbonButton(Icons.upload_file, 'Import Data', onTap: _importData),
        _ribbonButton(Icons.download, 'Export XLSX', onTap: _exportXlsx),
        _ribbonButton(Icons.table_view, 'Export CSV', onTap: _exportData),
        _ribbonButton(Icons.sync, 'Refresh'),
      ]),

      _ribbonGroup('Export', [
        _ribbonButton(Icons.download, 'Excel'),
        _ribbonButton(Icons.picture_as_pdf, 'PDF'),
        _ribbonButton(Icons.print, 'Print'),
      ]),
    ]);
  }

  void _clearFilter() {
    setState(() {
      _hiddenRows.clear();
    });
  }

  Widget _buildViewRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Show', [
        _ribbonButton(Icons.grid_on, 'Gridlines'),
        _ribbonButton(Icons.view_headline, 'Formula Bar'),
        _ribbonButton(Icons.view_column, 'Headings'),
      ]),
      _ribbonGroup('Window', [
        _ribbonButton(
          Icons.vertical_align_top,
          'Freeze Panes',
          onTap: _toggleFreezePanes,
        ),
        _ribbonButton(Icons.call_split, 'Split', onTap: _toggleSplit),
      ]),
      _ribbonGroup('Zoom', [
        _ribbonButton(Icons.zoom_in, 'Zoom In', onTap: _zoomIn),
        _ribbonButton(Icons.zoom_out, 'Zoom Out', onTap: _zoomOut),
      ]),
      _ribbonGroup('Window', [
        _ribbonButton(
          Icons.vertical_align_top,
          'Freeze Top Row',
          onTap: _toggleFreezeTopRow,
        ),
      ]),
      _ribbonButton(
        Icons.vertical_split,
        'Freeze First Column',
        onTap: _toggleFreezeFirstColumn,
      ),
    ]);
  }

  Widget _buildReportsRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Sales', [
        _ribbonButton(Icons.point_of_sale, 'Sales Report'),
        _ribbonButton(Icons.bar_chart, 'Sales Chart'),
      ]),
      _ribbonGroup('Inventory', [
        _ribbonButton(Icons.inventory_2, 'Stock Report'),
        _ribbonButton(Icons.warning_amber, 'Expiry Report'),
      ]),
      _ribbonGroup('Ledger', [
        _ribbonButton(Icons.people, 'Customer Ledger'),
        _ribbonButton(Icons.local_shipping, 'Supplier Ledger'),
      ]),
      _ribbonGroup('Profit', [
        _ribbonButton(Icons.trending_up, 'Profit Report'),
        _ribbonButton(Icons.pie_chart, 'Expense Report'),
      ]),
    ]);
  }

  Widget _buildPharmacyRibbon() {
    return _ribbonContainer([
      _ribbonGroup('Transactions', [
        _ribbonButton(Icons.point_of_sale, 'New Sale'),
        _ribbonButton(Icons.shopping_cart, 'Purchase'),
      ]),
      _ribbonGroup('Master Data', [
        _ribbonButton(Icons.medication, 'Medicine'),
        _ribbonButton(Icons.people, 'Customer'),
        _ribbonButton(Icons.local_shipping, 'Supplier'),
      ]),
      _ribbonGroup('Management', [
        _ribbonButton(Icons.inventory_2, 'Inventory'),
        _ribbonButton(Icons.receipt_long, 'Expense'),
        _ribbonButton(Icons.notifications, 'Reminder'),
      ]),
    ]);
  }

  Widget _buildFormulaBar() {
    return Container(
      height: 38,
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 90,
            height: 28,
            margin: const EdgeInsets.only(left: 6, right: 4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xffbdbdbd)),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(_selectedCell, style: const TextStyle(fontSize: 12)),
          ),
          const Icon(Icons.keyboard_arrow_down, size: 17),
          const SizedBox(width: 8),
          const Text(
            'fx',
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Color(0xff555555),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 28,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xffbdbdbd)),
              ),
              child: TextField(
                controller: _formulaController,
                focusNode: _formulaFocusNode,
                maxLines: 1,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                onChanged: (value) {},
                onSubmitted: (_) {
                  _commitFormulaBar();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorksheet() {
    if (_splitView) {
      return _buildSplitWorksheet();
    }
    if (_selectedSheet == 'Sales') {
      return _buildSalesSheet();
    }
    if (_selectedSheet == 'Purchases') {
      return _buildPurchasesSheet();
    }
    if (_selectedSheet == 'Inventory') {
      return _buildInventorySheet();
    }
    if (_selectedSheet == 'Supplier Ledger') {
      return _buildSupplierLedgerSheet();
    }
    if (_selectedSheet == 'Suppliers') {
      return _buildSuppliersSheet();
    }

    return Focus(
      focusNode: _gridFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        return _handleGridKey(event);
      },
      child: GestureDetector(
        onPanStart: (details) {
          _isDraggingSelection = true;
          _updateSelectionFromPointer(details.localPosition);

          if (_selectionAnchor == null) {
            setState(() {
              _selectionAnchor = _selectedCell;
              _selectionEnd = _selectedCell;
            });
          }
        },
        onPanUpdate: (details) {
          if (!_isDraggingSelection) return;
          _updateSelectionFromPointer(details.localPosition);
        },
        onPanEnd: (_) {
          _isDraggingSelection = false;
        },
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              // ============================================================
              // FROZEN TOP ROW
              // ============================================================
              if (_freezeTopRow)
                Row(
                  children: [
                    if (_freezeFirstColumn) _buildFrozenHeaderPart(),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _headerHorizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _freezeFirstColumn ? 1750 : 1900,
                          child: _freezeFirstColumn
                              ? _buildScrollableHeaderPart()
                              : _buildColumnHeaders(),
                        ),
                      ),
                    ),
                  ],
                ),

              // ============================================================
              // MAIN WORKSHEET
              // ============================================================
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ------------------------------------------------------
                    // FROZEN FIRST COLUMN
                    // ------------------------------------------------------
                    if (_freezeFirstColumn)
                      SizedBox(
                        width: 115,
                        child: SingleChildScrollView(
                          controller: _frozenVerticalScrollController,
                          child: Column(
                            children: [
                              if (!_freezeTopRow) _buildFrozenHeaderPart(),

                              ...List.generate(
                                100,
                                (index) => _buildFrozenRowPart(index + 1),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ------------------------------------------------------
                    // SCROLLABLE GRID
                    // ------------------------------------------------------
                    Expanded(
                      child: RawScrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        thickness: 10,
                        radius: const Radius.circular(5),
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.vertical,
                        child: RawScrollbar(
                          controller: _horizontalScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          thickness: 10,
                          radius: const Radius.circular(5),
                          scrollbarOrientation: ScrollbarOrientation.bottom,
                          notificationPredicate: (notification) =>
                              notification.metrics.axis == Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _freezeFirstColumn ? 1750 : 1900,
                              child: SingleChildScrollView(
                                controller: _verticalScrollController,
                                child: Column(
                                  children: [
                                    if (!_freezeTopRow && !_freezeFirstColumn)
                                      _buildColumnHeaders(),

                                    if (!_freezeFirstColumn)
                                      ...List.generate(
                                        100,
                                        (index) => _buildRow(index + 1),
                                      )
                                    else
                                      ...List.generate(
                                        100,
                                        (index) =>
                                            _buildScrollableRowPart(index + 1),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplitWorksheet() {
    final splitRow = _splitRow ?? 10;
    final splitColumn = _splitColumn ?? 4;

    final rowHeaderWidth = 45.0 * _zoom;
    final columnWidth = 70.0 * _zoom;
    final rowHeight = 24.0 * _zoom;

    final leftWidth = rowHeaderWidth + (splitColumn * columnWidth);

    final topHeight = splitRow * rowHeight;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_splitView) return;

      final horizontalOffset = rowHeaderWidth + (splitColumn * columnWidth);

      final verticalOffset = splitRow * rowHeight;

      // ==========================================================
      // TOP LEFT
      // ==========================================================
      if (_splitTopLeftHorizontalController.hasClients) {
        _splitTopLeftHorizontalController.jumpTo(0);
      }

      if (_splitTopLeftVerticalController.hasClients) {
        _splitTopLeftVerticalController.jumpTo(0);
      }

      // ==========================================================
      // TOP RIGHT
      // ==========================================================
      if (_splitTopRightHorizontalController.hasClients) {
        final max = _splitTopRightHorizontalController.position.maxScrollExtent;

        _splitTopRightHorizontalController.jumpTo(
          horizontalOffset.clamp(0.0, max),
        );
      }

      if (_splitTopRightVerticalController.hasClients) {
        _splitTopRightVerticalController.jumpTo(0);
      }

      // ==========================================================
      // BOTTOM LEFT
      // ==========================================================
      if (_splitBottomLeftHorizontalController.hasClients) {
        _splitBottomLeftHorizontalController.jumpTo(0);
      }

      if (_splitBottomLeftVerticalController.hasClients) {
        final max = _splitBottomLeftVerticalController.position.maxScrollExtent;

        _splitBottomLeftVerticalController.jumpTo(
          verticalOffset.clamp(0.0, max),
        );
      }

      // ==========================================================
      // BOTTOM RIGHT
      // ==========================================================
      if (_splitBottomRightHorizontalController.hasClients) {
        final max =
            _splitBottomRightHorizontalController.position.maxScrollExtent;

        _splitBottomRightHorizontalController.jumpTo(
          horizontalOffset.clamp(0.0, max),
        );
      }

      if (_splitBottomRightVerticalController.hasClients) {
        final max =
            _splitBottomRightVerticalController.position.maxScrollExtent;

        _splitBottomRightVerticalController.jumpTo(
          verticalOffset.clamp(0.0, max),
        );
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the split divider inside the available viewport.
        const double dividerWidth = 3.0;
        const double dividerHeight = 3.0;

        // Leave enough space for the right pane.
        const double minimumRightWidth = 100.0;

        // Leave enough space for the bottom pane.
        const double minimumBottomHeight = 100.0;

        final safeLeftWidth = leftWidth.clamp(
          0.0,
          (constraints.maxWidth - dividerWidth - minimumRightWidth).clamp(
            0.0,
            double.infinity,
          ),
        );

        final safeTopHeight = topHeight.clamp(
          0.0,
          (constraints.maxHeight - dividerHeight - minimumBottomHeight).clamp(
            0.0,
            double.infinity,
          ),
        );

        return Column(
          children: [
            // ==========================================================
            // TOP PANES
            // ==========================================================
            SizedBox(
              height: safeTopHeight,
              child: Row(
                children: [
                  // ======================================================
                  // TOP LEFT
                  // ======================================================
                  SizedBox(
                    width: safeLeftWidth,
                    child: _buildSplitPane(
                      verticalController: _splitTopLeftVerticalController,
                      horizontalController: _splitTopLeftHorizontalController,
                      startRow: 1,
                      endRow: splitRow,
                      startColumn: 1,
                      endColumn: splitColumn,
                    ),
                  ),

                  // ======================================================
                  // VERTICAL SPLIT DIVIDER
                  // ======================================================
                  Container(
                    width: dividerWidth,
                    color: const Color(0xff7f7f7f),
                  ),

                  // ======================================================
                  // TOP RIGHT
                  // ======================================================
                  Expanded(
                    child: _buildSplitPane(
                      verticalController: _splitTopRightVerticalController,
                      horizontalController: _splitTopRightHorizontalController,
                      startRow: 1,
                      endRow: splitRow,
                      startColumn: splitColumn + 1,
                      endColumn: 26,
                    ),
                  ),
                ],
              ),
            ),

            // ==========================================================
            // HORIZONTAL SPLIT DIVIDER
            // ==========================================================
            Container(height: dividerHeight, color: const Color(0xff7f7f7f)),

            // ==========================================================
            // BOTTOM PANES
            // ==========================================================
            Expanded(
              child: Row(
                children: [
                  // ======================================================
                  // BOTTOM LEFT
                  // ======================================================
                  SizedBox(
                    width: safeLeftWidth,
                    child: _buildSplitPane(
                      verticalController: _splitBottomLeftVerticalController,
                      horizontalController:
                          _splitBottomLeftHorizontalController,
                      startRow: splitRow + 1,
                      endRow: 100,
                      startColumn: 1,
                      endColumn: splitColumn,
                    ),
                  ),

                  // ======================================================
                  // VERTICAL SPLIT DIVIDER
                  // ======================================================
                  Container(
                    width: dividerWidth,
                    color: const Color(0xff7f7f7f),
                  ),

                  // ======================================================
                  // BOTTOM RIGHT
                  // ======================================================
                  Expanded(
                    child: _buildSplitPane(
                      verticalController: _splitBottomRightVerticalController,
                      horizontalController:
                          _splitBottomRightHorizontalController,
                      startRow: splitRow + 1,
                      endRow: 100,
                      startColumn: splitColumn + 1,
                      endColumn: 26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSplitPane({
    required ScrollController verticalController,
    required ScrollController horizontalController,
    required int startRow,
    required int endRow,
    required int startColumn,
    required int endColumn,
  }) {
    const int totalRows = 100;
    const int baseDataColumns = 26;

    return LayoutBuilder(
      builder: (context, constraints) {
        // ============================================================
        // ZOOM-AWARE DIMENSIONS
        // ============================================================
        final double rowHeaderWidth = 45.0 * _zoom;
        final double columnWidth = 70.0 * _zoom;
        final double rowHeight = 24.0 * _zoom;

        // ============================================================
        // KEEP ENOUGH WORKSHEET WIDTH AT ALL ZOOM LEVELS
        //
        // At low zoom, 26 columns may become smaller than the pane.
        // Add invisible/blank worksheet columns so horizontal
        // scrolling remains available, similar to Excel.
        // ============================================================
        final int visibleColumns =
            ((constraints.maxWidth - rowHeaderWidth) / columnWidth).ceil();

        final int totalDataColumns = visibleColumns + 10 > baseDataColumns
            ? visibleColumns + 10
            : baseDataColumns;

        const int rowNumberColumn = 1;
        final int totalColumns = totalDataColumns + rowNumberColumn;

        // ============================================================
        // TOTAL WORKSHEET WIDTH
        // ============================================================
        final double worksheetWidth =
            rowHeaderWidth + (totalDataColumns * columnWidth);

        // ============================================================
        // WORKSHEET
        // ============================================================
        return Container(
          color: Colors.white,
          child: Scrollbar(
            controller: verticalController,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (notification) {
              return notification.metrics.axis == Axis.vertical;
            },
            child: Scrollbar(
              controller: horizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notification) {
                return notification.metrics.axis == Axis.horizontal;
              },
              child: SizedBox(
                width: worksheetWidth > constraints.maxWidth
                    ? worksheetWidth
                    : constraints.maxWidth + 1,
                child: TableView.builder(
                  // ========================================================
                  // HORIZONTAL SCROLLING
                  // ========================================================
                  horizontalDetails: ScrollableDetails.horizontal(
                    controller: horizontalController,
                  ),

                  // ========================================================
                  // VERTICAL SCROLLING
                  // ========================================================
                  verticalDetails: ScrollableDetails.vertical(
                    controller: verticalController,
                  ),

                  // ========================================================
                  // DIAGONAL SCROLLING
                  // ========================================================
                  diagonalDragBehavior: DiagonalDragBehavior.free,

                  // ========================================================
                  // KEEP ROW NUMBERS VISIBLE
                  // ========================================================
                  pinnedColumnCount: 1,

                  // ========================================================
                  // WORKSHEET SIZE
                  // ========================================================
                  columnCount: totalColumns,
                  rowCount: totalRows,

                  // ========================================================
                  // COLUMNS
                  // ========================================================
                  columnBuilder: (column) {
                    if (column == 0) {
                      return TableSpan(
                        extent: FixedTableSpanExtent(rowHeaderWidth),
                      );
                    }

                    return TableSpan(extent: FixedTableSpanExtent(columnWidth));
                  },

                  // ========================================================
                  // ROWS
                  // ========================================================
                  rowBuilder: (row) {
                    return TableSpan(extent: FixedTableSpanExtent(rowHeight));
                  },

                  // ========================================================
                  // CELLS
                  // ========================================================
                  cellBuilder: (context, vicinity) {
                    final int actualRow = vicinity.row + 1;
                    final int column = vicinity.column;

                    // ======================================================
                    // ROW NUMBER
                    // ======================================================
                    if (column == 0) {
                      return TableViewCell(
                        child: Container(
                          width: rowHeaderWidth,
                          height: rowHeight,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xffe7e6e6),
                            border: Border(
                              right: BorderSide(color: Color(0xffc6c6c6)),
                              bottom: BorderSide(color: Color(0xffd9d9d9)),
                            ),
                          ),
                          child: Text(
                            '$actualRow',
                            style: TextStyle(fontSize: 11 * _zoom),
                          ),
                        ),
                      );
                    }

                    // ======================================================
                    // SPREADSHEET CELL
                    // ======================================================
                    final int actualColumn = column;

                    final String address =
                        '${_columnName(actualColumn - 1)}$actualRow';

                    return TableViewCell(
                      child: _buildCell(address, columnWidth),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrozenRowPart(int row) {
    if (_hiddenRows.contains(row)) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Container(
          width: 45 * _zoom,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xffe7e6e6),
            border: Border(
              right: BorderSide(color: Color(0xffc6c6c6)),
              bottom: BorderSide(color: Color(0xffd9d9d9)),
            ),
          ),
          child: Text('$row', style: const TextStyle(fontSize: 11)),
        ),
        _buildCell('A$row', 70),
      ],
    );
  }

  Widget _buildScrollableRowPart(int row) {
    if (_hiddenRows.contains(row)) {
      return const SizedBox.shrink();
    }

    return Row(
      children: List.generate(25, (index) {
        final column = index + 1;
        final cell = '${_columnName(column)}$row';

        return _buildCell(cell, 70);
      }),
    );
  }

  Widget _buildFrozenHeaderPart() {
    final rowHeaderWidth = 45.0 * _zoom;
    final columnWidth = 70.0 * _zoom;
    final rowHeight = 24.0 * _zoom;

    return Row(
      children: [
        Container(
          width: rowHeaderWidth,
          height: rowHeight,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xffe7e6e6),
            border: Border(
              right: BorderSide(color: Color(0xffc6c6c6)),
              bottom: BorderSide(color: Color(0xffc6c6c6)),
            ),
          ),
        ),

        Container(
          width: columnWidth,
          height: rowHeight,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xffe7e6e6),
            border: Border(
              right: BorderSide(color: Color(0xffc6c6c6)),
              bottom: BorderSide(color: Color(0xffc6c6c6)),
            ),
          ),
          child: Text(
            'A',
            style: TextStyle(fontSize: 11 * _zoom, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollableHeaderPart() {
    return Row(
      children: List.generate(25, (index) {
        final column = index + 1;

        return Container(
          width: 70,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xffe7e6e6),
            border: Border(
              right: BorderSide(color: Color(0xffc6c6c6)),
              bottom: BorderSide(color: Color(0xffc6c6c6)),
            ),
          ),
          child: Text(
            _columnName(column),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        );
      }),
    );
  }

  Widget _buildSuppliersSheet() {
    final query = _supplierSearch.trim().toLowerCase();
    final suppliers = _suppliers.where((supplier) {
      if (query.isEmpty) return true;
      return supplier.id.toLowerCase().contains(query) ||
          supplier.name.toLowerCase().contains(query) ||
          (supplier.phone ?? '').toLowerCase().contains(query) ||
          (supplier.gstin ?? '').toLowerCase().contains(query);
    }).toList();

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xffe2f0d9),
            child: Row(
              children: [
                const Icon(
                  Icons.local_shipping,
                  size: 18,
                  color: Color(0xff217346),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Suppliers',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 260,
                  height: 32,
                  child: TextField(
                    controller: _supplierSearchController,
                    onChanged: (value) =>
                        setState(() => _supplierSearch = value),
                    decoration: InputDecoration(
                      hintText: 'Search supplier...',
                      prefixIcon: const Icon(Icons.search, size: 17),
                      suffixIcon: _supplierSearch.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _supplierSearchController.clear();
                                setState(() => _supplierSearch = '');
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showAddSupplierDialog,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Add Supplier'),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Refresh suppliers',
                  onPressed: _loadSupplierData,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: suppliers.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty
                          ? 'No suppliers found. Click Add Supplier to create one.'
                          : 'No suppliers match "$query".',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xfff3f3f3),
                        ),
                        headingTextStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        dataTextStyle: const TextStyle(fontSize: 11),
                        columns: const [
                          DataColumn(label: Text('ID')),
                          DataColumn(label: Text('Supplier')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Address')),
                          DataColumn(label: Text('GSTIN')),
                          DataColumn(
                            label: Text('Opening Balance'),
                            numeric: true,
                          ),
                          DataColumn(label: Text('Current Due'), numeric: true),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: suppliers.map((supplier) {
                          final due = _supplierDues[supplier.id] ?? 0.0;
                          return DataRow(
                            cells: [
                              DataCell(Text(supplier.id)),
                              DataCell(Text(supplier.name)),
                              DataCell(Text(supplier.phone ?? '')),
                              DataCell(Text(supplier.address ?? '')),
                              DataCell(Text(supplier.gstin ?? '')),
                              DataCell(
                                Text(
                                  supplier.openingBalance.toStringAsFixed(2),
                                ),
                              ),
                              DataCell(
                                Text(
                                  due > 0
                                      ? 'Due ${due.toStringAsFixed(2)}'
                                      : due < 0
                                      ? 'Advance ${(-due).toStringAsFixed(2)}'
                                      : 'Settled',
                                  style: TextStyle(
                                    color: due > 0
                                        ? Colors.red.shade700
                                        : due < 0
                                        ? const Color(0xff217346)
                                        : Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const DataCell(Text('Active')),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit supplier',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                      icon: const Icon(Icons.edit, size: 16),
                                      onPressed: () =>
                                          _showEditSupplierDialog(supplier),
                                    ),
                                    IconButton(
                                      tooltip: 'Record payment',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                      icon: const Icon(
                                        Icons.payments_outlined,
                                        size: 16,
                                      ),
                                      onPressed: () =>
                                          _showSupplierPaymentDialog(supplier),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete supplier',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 16,
                                      ),
                                      onPressed: () =>
                                          _deleteSupplier(supplier),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSupplierData() async {
    final suppliers = await supplierRepository.getAll();
    final dues = <String, double>{};

    for (final supplier in suppliers) {
      try {
        dues[supplier.id] = await supplierRepository.getDue(supplier.id);
      } catch (_) {
        dues[supplier.id] = supplier.openingBalance;
      }
    }

    if (!mounted) return;

    setState(() {
      _suppliers = suppliers;
      _supplierDues
        ..clear()
        ..addAll(dues);
    });

    await _loadPurchaseData();

    // Refresh supplier ledger after supplier/purchase data changes.
    _loadSupplierLedger();
  }

  Future<void> _showAddSupplierDialog() async {
    await _showSupplierForm();
  }

  Future<void> _showEditSupplierDialog(Supplier supplier) async {
    await _showSupplierForm(existing: supplier);
  }

  Future<void> _showSupplierForm({Supplier? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final addressController = TextEditingController(
      text: existing?.address ?? '',
    );
    final gstinController = TextEditingController(text: existing?.gstin ?? '');
    final openingController = TextEditingController(
      text: existing?.openingBalance.toString() ?? '0',
    );
    final formKey = GlobalKey<FormState>();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(existing == null ? 'Add Supplier' : 'Edit Supplier'),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Supplier Name *',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Supplier name is required'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: 'Address'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: gstinController,
                        decoration: const InputDecoration(labelText: 'GSTIN'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: openingController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Opening Balance',
                        ),
                        validator: (value) {
                          final amount = double.tryParse(value?.trim() ?? '');
                          return amount == null || amount < 0
                              ? 'Enter a valid non-negative amount'
                              : null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final opening = double.parse(openingController.text.trim());
                  try {
                    if (existing == null) {
                      final id = 'SUP-${DateTime.now().microsecondsSinceEpoch}';
                      await supplierRepository.insertSupplier(
                        id: id,
                        name: nameController.text.trim(),
                        phone: _nullableText(phoneController.text),
                        address: _nullableText(addressController.text),
                        gstin: _nullableText(gstinController.text),
                        openingBalance: opening,
                      );
                    } else {
                      await supplierRepository.updateSupplier(
                        id: existing.id,
                        name: nameController.text.trim(),
                        phone: _nullableText(phoneController.text),
                        address: _nullableText(addressController.text),
                        gstin: _nullableText(gstinController.text),
                        openingBalance: opening,
                      );
                    }
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Supplier could not be saved: $error'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save Supplier'),
              ),
            ],
          );
        },
      );
      if (saved == true) {
        await _loadSupplierData();
        if (mounted) {
          _showSalesMessage(
            existing == null
                ? 'Supplier added successfully.'
                : 'Supplier updated successfully.',
          );
        }
      }
    } finally {
      nameController.dispose();
      phoneController.dispose();
      addressController.dispose();
      gstinController.dispose();
      openingController.dispose();
    }
  }

  String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _showSupplierPaymentDialog(Supplier supplier) async {
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    String paymentMethod = 'CASH';

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text('Record Payment — ${supplier.name}'),
                content: SizedBox(
                  width: 430,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount *',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                          DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                          DropdownMenuItem(
                            value: 'BANK',
                            child: Text('Bank Transfer'),
                          ),
                          DropdownMenuItem(value: 'CARD', child: Text('Card')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => paymentMethod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Reference No.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'Notes'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final amount = double.tryParse(
                        amountController.text.trim(),
                      );
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid payment amount.'),
                          ),
                        );
                        return;
                      }
                      try {
                        await supplierRepository.recordPayment(
                          paymentId:
                              'SPAY-${DateTime.now().microsecondsSinceEpoch}',
                          supplierId: supplier.id,
                          amount: amount,
                          paymentDate: DateTime.now(),
                          paymentMethod: paymentMethod,
                          referenceNo: _nullableText(referenceController.text),
                          notes: _nullableText(notesController.text),
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Payment could not be saved: $error',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Save Payment'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (saved == true) {
        await _loadSupplierData();
        if (mounted) {
          _showSalesMessage('Supplier payment recorded successfully.');
        }
      }
    } finally {
      amountController.dispose();
      referenceController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final purchaseRefs = await (_database.select(
      _database.purchases,
    )..where((tbl) => tbl.supplierId.equals(supplier.id))).get();
    final paymentRefs = await (_database.select(
      _database.supplierPayments,
    )..where((tbl) => tbl.supplierId.equals(supplier.id))).get();
    final batchRefs = await (_database.select(
      _database.batches,
    )..where((tbl) => tbl.supplierId.equals(supplier.id))).get();

    if (purchaseRefs.isNotEmpty ||
        paymentRefs.isNotEmpty ||
        batchRefs.isNotEmpty) {
      if (mounted) {
        _showSalesMessage(
          'Supplier cannot be deleted because transaction records exist.',
        );
      }
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Delete supplier "${supplier.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await supplierRepository.deleteSupplier(supplier.id);
    await _loadSupplierData();
    if (mounted) _showSalesMessage('Supplier deleted successfully.');
  }

  Widget _buildInventorySheet() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xffe2f0d9),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2,
                  size: 18,
                  color: Color(0xff217346),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Current Inventory',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh inventory',
                  onPressed: _loadInventoryData,
                  icon: const Icon(Icons.refresh, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 30,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xfff3f3f3),
                  ),
                  headingTextStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  dataTextStyle: const TextStyle(fontSize: 11),
                  columns: const [
                    DataColumn(label: Text('Medicine')),
                    DataColumn(label: Text('Batch No')),
                    DataColumn(label: Text('Expiry')),
                    DataColumn(label: Text('Supplier')),
                    DataColumn(label: Text('Purchase Rate'), numeric: true),
                    DataColumn(label: Text('MRP'), numeric: true),
                    DataColumn(label: Text('GST'), numeric: true),
                    DataColumn(label: Text('Purchased Qty'), numeric: true),
                    DataColumn(label: Text('Sold Qty'), numeric: true),
                    DataColumn(label: Text('Current Stock'), numeric: true),
                    DataColumn(label: Text('Stock Status')),
                  ],
                  rows: _inventoryItems.map((item) {
                    final expired = item.isExpired;
                    return DataRow(
                      color: WidgetStateProperty.resolveWith((states) {
                        if (expired) return const Color(0xfffff2f2);
                        return null;
                      }),
                      cells: [
                        DataCell(Text(item.medicine)),
                        DataCell(Text(item.batchNo)),
                        DataCell(
                          Text(
                            '${item.expiryDate.day.toString().padLeft(2, '0')}-'
                            '${item.expiryDate.month.toString().padLeft(2, '0')}-'
                            '${item.expiryDate.year}'
                            '${expired ? ' (Expired)' : ''}',
                            style: TextStyle(
                              color: expired ? Colors.red.shade700 : null,
                              fontWeight: expired ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                        DataCell(Text(item.supplier)),
                        DataCell(Text(item.purchaseRate.toStringAsFixed(2))),
                        DataCell(Text(item.mrp.toStringAsFixed(2))),
                        DataCell(
                          Text('${item.gstPercent.toStringAsFixed(2)}%'),
                        ),
                        DataCell(Text('${item.purchasedQuantity}')),
                        DataCell(Text('${item.soldQuantity}')),
                        DataCell(Text('${item.currentStock}')),
                        DataCell(
                          Text(
                            item.stockStatus,
                            style: TextStyle(
                              color: item.currentStock == 0
                                  ? Colors.red.shade700
                                  : const Color(0xff217346),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeaders() {
    final rowHeaderWidth = 45.0 * _zoom;
    final columnWidth = 70.0 * _zoom;
    final rowHeight = 24.0 * _zoom;

    return Row(
      children: [
        Container(
          width: rowHeaderWidth,
          height: rowHeight,
          decoration: const BoxDecoration(
            color: Color(0xffe7e6e6),
            border: Border(
              right: BorderSide(color: Color(0xffc6c6c6)),
              bottom: BorderSide(color: Color(0xffc6c6c6)),
            ),
          ),
        ),
        ...List.generate(26, (index) {
          return _headerCell(_columnName(index), columnWidth);
        }),
      ],
    );
  }

  Widget _buildRow(int row) {
    if (_hiddenRows.contains(row)) {
      return const SizedBox.shrink();
    }

    final rowHeaderWidth = 45.0 * _zoom;
    final columnWidth = 70.0 * _zoom;
    final rowHeight = 24.0 * _zoom;

    return Row(
      children: [
        Container(
          width: rowHeaderWidth,
          height: rowHeight,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xffe7e6e6),
            border: Border(
              right: BorderSide(color: Color(0xffc6c6c6)),
              bottom: BorderSide(color: Color(0xffd9d9d9)),
            ),
          ),
          child: Text('$row', style: TextStyle(fontSize: 11 * _zoom)),
        ),
        ...List.generate(26, (column) {
          final cell = '${_columnName(column)}$row';

          return _buildCell(cell, columnWidth, height: rowHeight);
        }),
      ],
    );
  }

  Widget _headerCell(String text, double width) {
    return Container(
      width: width,
      height: 24,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xffe7e6e6),
        border: Border(
          right: BorderSide(color: Color(0xffc6c6c6)),
          bottom: BorderSide(color: Color(0xffc6c6c6)),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildCell(String address, double width, {double height = 24}) {
    final selected =
        address == _selectedCell || _selectedRangeCells().contains(address);
    final value = _cells[address] ?? '';
    final validationValues = _cellValidations[address];

    return GestureDetector(
      onTap: () {
        if (_editingCell != null) {
          _commitCellEdit();
        }

        setState(() {
          _selectedCell = address;

          // Start a new single-cell selection.
          _selectionAnchor = address;
          _selectionEnd = address;

          _formulaController.text = _cells[address] ?? '';
        });

        _gridFocusNode.requestFocus();
      },
      onDoubleTap: () async {
        String editedValue = _cells[address] ?? '';

        final result = await showDialog<String>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('Edit $address'),
              content: TextFormField(
                initialValue: editedValue,
                autofocus: true,
                maxLines: 1,
                onChanged: (value) {
                  editedValue = value;
                },
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context, editedValue);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );

        if (!mounted) return;

        if (result != null) {
          setState(() {
            if (result.isEmpty) {
              _cells.remove(address);
            } else {
              _cells[address] = result;
            }

            _formulaController.text = result;
          });
        }
      },
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            right: const BorderSide(color: Color(0xffdddddd)),
            bottom: const BorderSide(color: Color(0xffdddddd)),
            top: selected
                ? const BorderSide(color: Color(0xff217346), width: 2)
                : BorderSide.none,
            left: selected
                ? const BorderSide(color: Color(0xff217346), width: 2)
                : BorderSide.none,
          ),
        ),
        child: _editingCell == address
            ? TextField(
                key: ValueKey('cell-editor-$address'),
                controller: _cellEditController,
                autofocus: true,
                maxLines: 1,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 3,
                  ),
                ),
                style: const TextStyle(fontSize: 11),
                onSubmitted: (_) {
                  final currentCell = _editingCell;

                  _commitCellEdit();

                  if (currentCell == null) return;

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;

                    _moveSelection(rowDelta: 1);
                  });
                },
              )
            : validationValues != null && validationValues.isNotEmpty
            ? DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: validationValues.contains(value) ? value : null,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 16),
                  hint: const Text('', style: TextStyle(fontSize: 11)),
                  items: validationValues.map((item) {
                    return DropdownMenuItem<String>(
                      value: item,
                      child: Text(
                        item,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue == null) return;

                    setState(() {
                      _cells[address] = newValue;
                      _selectedCell = address;
                      _selectionAnchor = address;
                      _selectionEnd = address;
                      _formulaController.text = newValue;
                    });

                    _gridFocusNode.requestFocus();
                  },
                ),
              )
            : Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontSize: 11),
              ),
      ),
    );
  }

  Widget _buildSheetTabs() {
    return Container(
      height: 30,
      color: const Color(0xfff3f3f3),
      child: Row(
        children: [
          IconButton(
            tooltip: 'All Sheets',
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            icon: const Icon(Icons.menu, size: 16),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._sheetTabs.map((sheet) {
                  final selected = sheet == _selectedSheet;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedSheet = sheet;
                      });
                      if (sheet == 'Inventory') {
                        _loadInventoryData();
                      }
                      if (sheet == 'Suppliers') {
                        _loadSupplierData();
                      }
                      if (sheet == 'Purchases') {
                        _loadPurchaseData();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : const Color(0xffe6e6e6),
                        border: Border(
                          right: const BorderSide(color: Color(0xffcccccc)),
                          top: BorderSide(
                            color: selected
                                ? const Color(0xff217346)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        sheet,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  );
                }),
                IconButton(
                  tooltip: 'New Sheet',
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 30,
                  ),
                  icon: const Icon(Icons.add, size: 17),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      color: const Color(0xff217346),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Text(
            'Ready',
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(width: 24),
          Text(
            'Sheet: $_selectedSheet',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          const Spacer(),
          Text(
            'Records: 0',
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(width: 20),
          Text(
            '${(_zoom * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.remove, color: Colors.white, size: 14),
          SizedBox(
            width: 100,
            child: Slider(
              value: _zoom,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              onChanged: _setZoom,
            ),
          ),
          const Icon(Icons.add, color: Colors.white, size: 14),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  int _columnNumber(String column) {
    var result = 0;

    for (final char in column.codeUnits) {
      result = result * 26 + char - 64;
    }

    return result;
  }

  String _columnName(int index) {
    var number = index + 1;
    var result = '';

    while (number > 0) {
      number--;
      result = String.fromCharCode(65 + number % 26) + result;
      number ~/= 26;
    }

    return result;
  }

  @override
  void dispose() {
    _splitTopLeftVerticalController.dispose();
    _splitTopLeftHorizontalController.dispose();

    _splitTopRightVerticalController.dispose();
    _splitTopRightHorizontalController.dispose();

    _splitBottomLeftVerticalController.dispose();
    _splitBottomLeftHorizontalController.dispose();

    _splitBottomRightVerticalController.dispose();
    _splitBottomRightHorizontalController.dispose();
    _splitTopLeftVerticalController.dispose();
    _splitTopRightVerticalController.dispose();
    _splitTopRightHorizontalController.dispose();
    _splitBottomLeftHorizontalController.dispose();
    _splitBottomRightVerticalController.dispose();
    _splitBottomRightHorizontalController.dispose();
    _headerHorizontalScrollController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _frozenVerticalScrollController.dispose();
    _cellEditController.dispose();
    _cellEditFocusNode.dispose();
    _formulaController.dispose();
    _formulaFocusNode.dispose();
    _gridFocusNode.dispose();
    _salesInvoiceController.dispose();
    _salesQtyController.dispose();
    _salesRateController.dispose();
    _salesDiscountController.dispose();
    _salesPaidController.dispose();
    _purchaseInvoiceController.dispose();
    _purchaseBatchController.dispose();
    _purchaseDateController.dispose();
    _purchaseQtyController.dispose();
    _purchaseRateController.dispose();
    _purchaseMrpController.dispose();
    _purchaseGstController.dispose();
    _supplierSearchController.dispose();
    if (_ownsDatabase) {
      _database.close();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _syncFrozenVerticalScroll();
    _syncHeaderHorizontalScroll();

    _cellEditController = TextEditingController();
    _formulaController = TextEditingController();
    _salesInvoiceController = TextEditingController();
    _salesQtyController = TextEditingController(text: '1');
    _salesRateController = TextEditingController();
    _salesDiscountController = TextEditingController(text: '0');
    _salesPaidController = TextEditingController(text: '0');
    _purchaseInvoiceController = TextEditingController();
    _purchaseBatchController = TextEditingController();
    _purchaseDateController = TextEditingController(
      text: _formatSalesDate(DateTime.now()),
    );
    _purchaseQtyController = TextEditingController(text: '1');
    _purchaseRateController = TextEditingController();
    _purchaseMrpController = TextEditingController();
    _purchaseGstController = TextEditingController(text: '0');
    _supplierSearchController = TextEditingController();

    _database = widget.database ?? AppDatabase();
    _ownsDatabase = widget.database == null;

    stockRepository = StockRepository(_database);
    batchRepository = BatchRepository(_database);
    medicineRepository = MedicineRepository(_database);
    customerRepository = CustomerRepository(_database);
    saleRepository = SaleRepository(_database, stockRepository);
    purchaseRepository = PurchaseRepository(_database);
    supplierRepository = SupplierRepository(_database);
    inventoryRepository = InventoryRepository(_database);

    _loadSalesData();
    _loadPurchaseData();
    _loadInventoryData();
    _loadSupplierData();
  }

  Future<void> _loadSalesData() async {
    final medicines = await medicineRepository.getAll();
    final customers = await customerRepository.getAll();
    final batches = await batchRepository.getAll();
    if (!mounted) return;

    setState(() {
      _salesMedicines = medicines;
      _salesCustomers = customers;
      _salesBatches = batches;
      _purchaseMedicines = medicines;
    });
  }

  void _syncHeaderHorizontalScroll() {
    _horizontalScrollController.addListener(() {
      if (!_headerHorizontalScrollController.hasClients) return;

      final offset = _horizontalScrollController.offset.clamp(
        0.0,
        _headerHorizontalScrollController.position.maxScrollExtent,
      );

      if ((_headerHorizontalScrollController.offset - offset).abs() > 0.5) {
        _headerHorizontalScrollController.jumpTo(offset);
      }
    });
  }

  Future<void> _loadPurchaseData() async {
    final suppliers = await supplierRepository.getAll();
    final medicines = await medicineRepository.getAll();
    if (!mounted) return;
    setState(() {
      _purchaseSuppliers = suppliers;
      _purchaseMedicines = medicines;
    });
  }

  Future<void> _loadInventoryData() async {
    final inventoryItems = await inventoryRepository.getAll();
    if (!mounted) return;
    setState(() {
      _inventoryItems = inventoryItems;
    });
  }

  void _showFindDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Find'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Find what',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) {
                Navigator.pop(context);
                _findNext(controller.text);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text;
                Navigator.pop(context);
                _findNext(text);
              },
              child: const Text('Find Next'),
            ),
          ],
        );
      },
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sort'),
          content: const Text('Choose a sort direction.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _sortSelectedColumn(ascending: true);
              },
              child: const Text('A → Z'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _sortSelectedColumn(ascending: false);
              },
              child: const Text('Z → A'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showValidationDialog() {
    String validationText = '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Data Validation'),
          content: SizedBox(
            width: 420,
            child: TextFormField(
              autofocus: true,
              initialValue: '',
              maxLines: 1,
              onChanged: (value) {
                validationText = value;
              },
              decoration: const InputDecoration(
                labelText: 'List values',
                hintText: 'Cash, UPI, Card, Credit',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final values = validationText
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                if (values.isEmpty) {
                  return;
                }

                Navigator.pop(context, values);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    ).then((result) {
      if (!mounted) return;

      if (result is List<String> && result.isNotEmpty) {
        setState(() {
          _cellValidations[_selectedCell] = result;
        });
      }
    });
  }

  void _showFilterDialog() {
    final position = _cellPosition(_selectedCell);
    final column = position[0];

    final values = <String>{};

    for (final address in _cells.keys) {
      final cellPosition = _cellPosition(address);

      if (cellPosition[0] == column) {
        final value = _cells[address] ?? '';

        if (value.isNotEmpty) {
          values.add(value);
        }
      }
    }

    final sortedValues = values.toList()..sort();

    if (sortedValues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data found in the selected column.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        String? selectedValue;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter'),
              content: SizedBox(
                width: 350,
                height: 300,
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Show rows containing:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: RadioGroup<String>(
                        groupValue: selectedValue,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedValue = value;
                          });
                        },
                        child: ListView.builder(
                          itemCount: sortedValues.length,
                          itemBuilder: (context, index) {
                            final value = sortedValues[index];

                            return RadioListTile<String>(
                              value: value,
                              title: Text(value),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedValue == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          _applyFilter(column: column, value: selectedValue!);
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeDuplicates() {
    final selectedPosition = _cellPosition(_selectedCell);
    final column = selectedPosition[0];

    final maxRow = _cells.keys.fold<int>(1, (max, address) {
      final row = _cellPosition(address)[1];
      return row > max ? row : max;
    });

    final seenValues = <String>{};
    final rowsToKeep = <int>[];

    for (var row = 1; row <= maxRow; row++) {
      final address = _cellAddress(column, row);
      final value = (_cells[address] ?? '').trim();

      // Keep empty rows.
      if (value.isEmpty) {
        rowsToKeep.add(row);
        continue;
      }

      if (seenValues.add(value)) {
        rowsToKeep.add(row);
      }
    }

    final removedCount = maxRow - rowsToKeep.length;

    if (removedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No duplicate values found.')),
      );
      return;
    }

    _saveUndoState();

    final newCells = <String, String>{};
    var newRow = 1;

    for (final oldRow in rowsToKeep) {
      for (var col = 1; col <= 26; col++) {
        final oldAddress = _cellAddress(col, oldRow);
        final value = _cells[oldAddress];

        if (value != null && value.isNotEmpty) {
          final newAddress = _cellAddress(col, newRow);
          newCells[newAddress] = value;
        }
      }

      newRow++;
    }

    setState(() {
      _cells
        ..clear()
        ..addAll(newCells);

      _selectedCell = _cellAddress(column, 1);
      _selectionAnchor = _selectedCell;
      _selectionEnd = _selectedCell;

      _hiddenRows.clear();
    });

    _formulaController.text = _cells[_selectedCell] ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$removedCount duplicate row(s) removed.')),
    );
  }

  void _applyFilter({required int column, required String value}) {
    final hiddenRows = <int>{};

    final maxRow = _cells.keys.fold<int>(1, (max, address) {
      final row = _cellPosition(address)[1];
      return row > max ? row : max;
    });

    for (var row = 1; row <= maxRow; row++) {
      final address = _cellAddress(column, row);
      final cellValue = _cells[address] ?? '';

      if (cellValue != value) {
        hiddenRows.add(row);
      }
    }

    setState(() {
      _hiddenRows = hiddenRows;
    });
  }

  void _sortSelectedColumn({required bool ascending}) {
    final position = _cellPosition(_selectedCell);
    final column = position[0];

    // Find the last row containing data in this column.
    int lastRow = 0;

    for (final address in _cells.keys) {
      final cellPosition = _cellPosition(address);

      if (cellPosition[0] == column && cellPosition[1] > lastRow) {
        lastRow = cellPosition[1];
      }
    }

    if (lastRow <= 1) {
      return;
    }

    // Collect values from the selected column.
    final values = <String>[];

    for (int row = 1; row <= lastRow; row++) {
      final address = _cellAddress(column, row);
      values.add(_cells[address] ?? '');
    }

    // Nothing to sort.
    if (values.where((value) => value.isNotEmpty).length <= 1) {
      return;
    }

    _saveUndoState();

    values.sort((a, b) {
      // Keep blank cells at the bottom.
      if (a.isEmpty && b.isEmpty) {
        return 0;
      }

      if (a.isEmpty) {
        return 1;
      }

      if (b.isEmpty) {
        return -1;
      }

      // Try numeric comparison first.
      final numberA = double.tryParse(a);
      final numberB = double.tryParse(b);

      int result;

      if (numberA != null && numberB != null) {
        result = numberA.compareTo(numberB);
      } else {
        result = a.toLowerCase().compareTo(b.toLowerCase());
      }

      return ascending ? result : -result;
    });

    setState(() {
      for (int row = 1; row <= lastRow; row++) {
        final address = _cellAddress(column, row);
        final value = values[row - 1];

        if (value.isEmpty) {
          _cells.remove(address);
        } else {
          _cells[address] = value;
        }
      }
    });
  }

  void _findNext(String query) {
    final search = query.trim().toLowerCase();

    if (search.isEmpty) return;

    final cells = _cells.entries.toList();

    for (final entry in cells) {
      if (entry.value.toLowerCase().contains(search)) {
        setState(() {
          _selectedCell = entry.key;
          _selectionAnchor = entry.key;
          _selectionEnd = entry.key;
          _formulaController.text = entry.value;
        });

        _gridFocusNode.requestFocus();
        return;
      }
    }
  }

  void _startCellEditing({String? initialText}) {
    final value = initialText ?? _cells[_selectedCell] ?? '';

    setState(() {
      _editingCell = _selectedCell;
      _cellEditController.text = value;
      _cellEditController.selection = TextSelection.collapsed(
        offset: _cellEditController.text.length,
      );
    });
  }

  void _commitFormulaBar() {
    final value = _formulaController.text;
    final oldValue = _cells[_selectedCell] ?? '';

    if (value == oldValue) {
      _gridFocusNode.requestFocus();
      return;
    }

    _saveUndoState();

    setState(() {
      if (value.isEmpty) {
        _cells.remove(_selectedCell);
      } else {
        _cells[_selectedCell] = value;
      }
    });
    _recalculateSalesRowIfNeeded(_selectedCell);

    _gridFocusNode.requestFocus();
  }

  void _recalculateSalesRow(int row) {
    if (_selectedSheet != 'Sales') return;

    double number(String column) {
      return double.tryParse((_cells['$column$row'] ?? '').trim()) ?? 0.0;
    }

    final qty = number('F');
    final rate = number('G');
    final gstPercent = number('H');
    final discount = number('I');
    final paid = number('K');

    final subtotal = qty * rate;
    final gst = subtotal * gstPercent / 100;
    final total = subtotal + gst - discount;
    final due = total - paid;

    _cells['J$row'] = total.toStringAsFixed(2);
    _cells['L$row'] = due.toStringAsFixed(2);
  }

  void _recalculateSalesRowIfNeeded(String cell) {
    if (_selectedSheet != 'Sales') return;

    final match = RegExp(r'\d+$').firstMatch(cell);
    if (match == null) return;

    final row = int.tryParse(match.group(0)!);
    if (row == null || row < 1) return;

    _recalculateSalesRow(row);
  }

  void _commitCellEdit() {
    final cell = _editingCell;

    if (cell == null) {
      return;
    }

    final value = _cellEditController.text;

    setState(() {
      if (value.isEmpty) {
        _cells.remove(cell);
      } else {
        _cells[cell] = value;
      }

      _editingCell = null;
    });
  }

  void _cancelCellEdit() {
    setState(() {
      _editingCell = null;
    });
  }

  Widget _buildSupplierLedgerSheet() {
    final supplier = _suppliers.isNotEmpty ? _suppliers.first : null;

    if (supplier == null) {
      return const Center(
        child: Text(
          'No suppliers found.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    _supplierLedgerFuture ??= supplierRepository.getLedger(supplier.id);

    return FutureBuilder<List<SupplierLedgerEntry>>(
      future: _supplierLedgerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load supplier ledger: ${snapshot.error}',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          );
        }

        final entries = snapshot.data ?? [];

        return Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: const Color(0xffe2f0d9),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      size: 18,
                      color: Color(0xff217346),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Supplier Ledger',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      supplier.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text(
                          'No supplier transactions found.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xfff3f3f3),
                            ),
                            columns: const [
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Type')),
                              DataColumn(label: Text('Reference')),
                              DataColumn(label: Text('Debit'), numeric: true),
                              DataColumn(label: Text('Credit'), numeric: true),
                              DataColumn(
                                label: Text('Balance / Status'),
                                numeric: true,
                              ),
                            ],
                            rows: entries.map((entry) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      '${entry.date.day.toString().padLeft(2, '0')}/'
                                      '${entry.date.month.toString().padLeft(2, '0')}/'
                                      '${entry.date.year}',
                                    ),
                                  ),
                                  DataCell(Text(entry.type)),
                                  DataCell(Text(entry.reference)),
                                  DataCell(
                                    Text(entry.debit.toStringAsFixed(2)),
                                  ),
                                  DataCell(
                                    Text(entry.credit.toStringAsFixed(2)),
                                  ),
                                  DataCell(
                                    Text(
                                      entry.balance < 0
                                          ? 'Advance ${entry.balance.abs().toStringAsFixed(2)}'
                                          : entry.balance > 0
                                          ? 'Due ${entry.balance.toStringAsFixed(2)}'
                                          : 'Settled',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: entry.balance < 0
                                            ? const Color(0xff217346)
                                            : entry.balance > 0
                                            ? Colors.red.shade700
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
