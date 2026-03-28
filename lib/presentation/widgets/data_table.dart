import 'package:flutter/material.dart';

/// Column definition for GenericDataTable widget
class DataColumn<T> {
  final String label;
  final String? fieldName; // Property name to access from data object
  final dynamic Function(T)? getter; // Custom getter to extract value from item
  final double? width;
  final MainAxisAlignment alignment;
  final IconData? icon;
  final String Function(dynamic)? formatter; // Format callback for rendering
  final Widget Function(T, int)? cellBuilder; // Custom cell widget builder
  final bool isEditable;
  final Function(int, String)? onEdit; // Callback for edit operations

  DataColumn({
    required this.label,
    this.fieldName,
    this.getter,
    this.width,
    this.alignment = MainAxisAlignment.start,
    this.icon,
    this.formatter,
    this.cellBuilder,
    this.isEditable = false,
    this.onEdit,
  });
}

/// Professional configurable Data Table Widget
class GenericDataTable<T> extends StatefulWidget {
  final List<T> items;
  final List<DataColumn<T>> columns;
  final Function(int)? onDeleteRow;
  final Widget Function()? additionalRow;
  final Widget? totalRow;
  final Map<int, TextEditingController>? editControllers;

  const GenericDataTable({
    Key? key,
    required this.items,
    required this.columns,
    this.onDeleteRow,
    this.additionalRow,
    this.totalRow,
    this.editControllers,
  }) : super(key: key);

  @override
  State<GenericDataTable<T>> createState() => _GenericDataTableState<T>();
}

class _GenericDataTableState<T> extends State<GenericDataTable<T>> {
  Map<int, TextEditingController> controllers = {};

  @override
  void initState() {
    super.initState();
    controllers = widget.editControllers ?? {};
  }

  @override
  void dispose() {
    for (var controller in controllers.values) {
      if (!controllers.values.contains(controller)) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  dynamic _getFieldValue(T item, String fieldName) {
    if (item is Map) {
      return item[fieldName];
    }
    // For custom objects, require a getter. If not provided, return empty string.
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Table(
            columnWidths: _buildColumnWidths(),
            border: TableBorder(
              horizontalInside: BorderSide(
                color: Colors.grey.shade300,
                width: 1,
              ),
              bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade200),
                children: [
                  ...widget.columns.map((col) {
                    return Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        mainAxisAlignment: col.alignment,
                        children: [
                          if (col.icon != null) Icon(col.icon, size: 14),
                          if (col.icon != null) SizedBox(width: 4),
                          Text(
                            col.label,
                            style: TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  if (widget.onDeleteRow != null) SizedBox(),
                ],
              ),
            ],
          ),
        ),
        // Data Rows
        Flexible(
          fit: FlexFit.loose,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.items.length +
                (widget.additionalRow != null ? 1 : 0) +
                (widget.totalRow != null ? 1 : 0),
            itemBuilder: (_, rowIndex) {
              // Total row
              if (widget.totalRow != null &&
                  rowIndex ==
                      widget.items.length +
                          (widget.additionalRow != null ? 1 : 0)) {
                return widget.totalRow!;
              }

              // Additional row (e.g., "Select Product")
              if (widget.additionalRow != null &&
                  rowIndex == widget.items.length) {
                return widget.additionalRow!();
              }

              // Data row
              final item = widget.items[rowIndex];
              final isAlternate = rowIndex % 2 == 1;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Table(
                  columnWidths: _buildColumnWidths(),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: isAlternate ? Colors.grey.shade50 : Colors.white,
                      ),
                      children: [
                        ...widget.columns.map((col) {
                          // Use custom cell builder if provided
                          if (col.cellBuilder != null) {
                            return Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: col.cellBuilder!(item, rowIndex),
                            );
                          }

                          // Get field value - prefer custom getter if provided
                          final value = col.getter != null
                              ? col.getter!(item)
                              : col.fieldName != null
                                  ? _getFieldValue(item, col.fieldName!)
                                  : null;

                          // Format value if formatter provided
                          final displayValue = col.formatter != null
                              ? col.formatter!(value)
                              : value?.toString() ?? '';

                          return Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Row(
                              mainAxisAlignment: col.alignment,
                              children: [
                                Text(
                                  displayValue,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        if (widget.onDeleteRow != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Align(
                              alignment: Alignment.center,
                              child: InkWell(
                                onTap: () => widget.onDeleteRow!(rowIndex),
                                child: Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Map<int, TableColumnWidth> _buildColumnWidths() {
    Map<int, TableColumnWidth> widths = {};

    // Guidance: Item Name (flex: 3), Qty (flex: 1), Rate (flex: 1), Amount (flex: 1), Delete (fixed: 40)
    if (widget.columns.length >= 4) {
      widths[0] = const FlexColumnWidth(3); // Item Name
      widths[1] = const FlexColumnWidth(1); // Qty
      widths[2] = const FlexColumnWidth(1); // Rate
      widths[3] = const FlexColumnWidth(1); // Amount
    }
    if (widget.onDeleteRow != null) {
      widths[widget.columns.length] = const FixedColumnWidth(40);
    }
    return widths;
  }
}
