import 'dart:async';

import 'package:flutter/material.dart';

class SearchableDropdown<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(T item) itemBuilder;
  final String Function(T item) searchMatcher;
  final Function(T item) onSelected;
  final String hintText;
  final Widget Function(String searchQuery)? headerBuilder;
  final VoidCallback? onClear;
  final bool isSelected;
  final double maxHeight;

  const SearchableDropdown({
    Key? key,
    required this.items,
    required this.itemBuilder,
    required this.searchMatcher,
    required this.onSelected,
    this.hintText = "Select",
    this.headerBuilder,
    this.onClear,
    this.isSelected = false,
    this.maxHeight = 400,
  }) : super(key: key);

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  final TextEditingController _controller = TextEditingController();
  List<T> _filtered = [];
  Timer? _debounce;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  void _onSearch(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _filtered = widget.items.where((item) {
          return widget
              .searchMatcher(item)
              .toLowerCase()
              .contains(value.toLowerCase());
        }).toList();
      });
    });
  }

  void _toggleDropdown() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (!_isExpanded) {
        _controller.clear();
        _filtered = widget.items;
      }
    });
  }

  void _selectItem(T item) {
    widget.onSelected(item);
    setState(() {
      _isExpanded = false;
      _controller.clear();
      _filtered = widget.items;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle button
        GestureDetector(
          onTap: _toggleDropdown,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 12 : 10,
              vertical: isTablet ? 12 : 10,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isExpanded || widget.isSelected
                    ? const Color(0xFFFF8C42)
                    : Colors.grey.shade300,
                width: _isExpanded || widget.isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(_isExpanded ? 0 : 12),
                bottomRight: Radius.circular(_isExpanded ? 0 : 12),
              ),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade100,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.business,
                  size: isTablet ? 20 : 18,
                  color: _isExpanded || widget.isSelected
                      ? const Color(0xFFFF8C42)
                      : Colors.grey.shade400,
                ),
                SizedBox(width: isTablet ? 8 : 6),
                Expanded(
                  child: Text(
                    widget.hintText,
                    style: TextStyle(
                      color: _isExpanded || widget.isSelected
                          ? Colors.grey.shade900
                          : Colors.grey.shade500,
                      fontSize: isTablet ? 15 : 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.isSelected && widget.onClear != null)
                  GestureDetector(
                    onTap: () {
                      widget.onClear!();
                      setState(() => _isExpanded = false);
                    },
                    child: Icon(Icons.clear, size: isTablet ? 18 : 16),
                  )
                else
                  Icon(
                    _isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: isTablet ? 20 : 18,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          ),
        ),

        // Expanded content
        if (_isExpanded)
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: const Color(0xFFFF8C42),
                  width: 2,
                ),
                right: BorderSide(
                  color: const Color(0xFFFF8C42),
                  width: 2,
                ),
                bottom: BorderSide(
                  color: const Color(0xFFFF8C42),
                  width: 2,
                ),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (Add New Party)
                if (widget.headerBuilder != null)
                  widget.headerBuilder!(_controller.text.toLowerCase()),

                // Search field
                Padding(
                  padding: EdgeInsets.all(isTablet ? 12 : 10),
                  child: TextField(
                    controller: _controller,
                    onChanged: _onSearch,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 12 : 10,
                        vertical: isTablet ? 12 : 10,
                      ),
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),

                // List of items
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: widget.maxHeight,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (_, index) {
                      final item = _filtered[index];
                      return InkWell(
                        onTap: () => _selectItem(item),
                        child: widget.itemBuilder(item),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
