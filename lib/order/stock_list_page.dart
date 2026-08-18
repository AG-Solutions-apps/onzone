import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'app_theme.dart';

class StockListPage extends StatefulWidget {
  const StockListPage({super.key});

  @override
  State<StockListPage> createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  List<dynamic> _allStock = [];
  List<dynamic> _filteredStock = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _searchQuery = '';
  
  double _minStockFilter = 0;
  double _maxStockFilter = 100;
  double _absoluteMaxStock = 100;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAndRefreshStock();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAndRefreshStock() async {
    // 1. Load locally cached data first so UI responds instant
    await _loadLocalStock();
    
    // 2. Fetch latest data from the API in the background
    setState(() {
      _isRefreshing = true;
    });
    try {
      await fetchAndCacheStock();
      // 3. Reload from local storage
      await _loadLocalStock();
    } catch (e) {
      debugPrint('Error refreshing stock from API: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadLocalStock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stockStr = prefs.getString('fair_order_stock');
      if (stockStr != null) {
        final decoded = jsonDecode(stockStr);
        List<dynamic> loadedStock = [];
        if (decoded is Map && decoded['data'] is List) {
          loadedStock = decoded['data'];
        } else if (decoded is List) {
          loadedStock = decoded;
        }

        // Find absolute max stock in dataset
        double currentMax = 10;
        for (var item in loadedStock) {
          final rawStock = item['stock'];
          int s = 0;
          if (rawStock is num) {
            s = rawStock.toInt();
          } else if (rawStock is String) {
            s = int.tryParse(rawStock) ?? 0;
          }
          if (s > currentMax) {
            currentMax = s.toDouble();
          }
        }

        setState(() {
          _allStock = loadedStock;
          _absoluteMaxStock = currentMax;
          
          // Clamp filters in case new max is lower than before
          _maxStockFilter = _maxStockFilter.clamp(0.0, _absoluteMaxStock);
          _minStockFilter = _minStockFilter.clamp(0.0, _maxStockFilter);
          
          // Set to full range on first initial load
          if (_maxStockFilter == 100 || _maxStockFilter == 0) {
            _maxStockFilter = _absoluteMaxStock;
            _minStockFilter = 0;
          }
        });
        _applyFilters();
      }
    } catch (e) {
      debugPrint('Error loading stock from local cache: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchQuery.trim().toLowerCase();
    setState(() {
      _filteredStock = _allStock.where((item) {
        final rawStock = item['stock'];
        int stock = 0;
        if (rawStock is num) {
          stock = rawStock.toInt();
        } else if (rawStock is String) {
          stock = int.tryParse(rawStock) ?? 0;
        }
        
        // Stock Range Filter
        if (stock < _minStockFilter.toInt() || stock > _maxStockFilter.toInt()) {
          return false;
        }

        // Search Query Filter
        if (query.isNotEmpty) {
          final String barcode = (item['fair_barcode'] ?? '').toString().toLowerCase();
          final String mainBarcode = (item['fair_barcode_main'] ?? '').toString().toLowerCase();
          final String color = (item['fair_colour'] ?? '').toString().toLowerCase();
          final String dressType = (item['fair_dress_type'] ?? '').toString().toLowerCase();
          
          return barcode.contains(query) ||
              mainBarcode.contains(query) ||
              color.contains(query) ||
              dressType.contains(query);
        }

        return true;
      }).toList();
    });
  }

  Color _getStockColor(int stock) {
    if (stock <= 0) {
      return Colors.red;
    } else if (stock <= 10) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = AppTheme.primaryColor;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Local Stock Inventory',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadAndRefreshStock,
              tooltip: 'Sync Local Cache',
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filters Section
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search Input Field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by style, barcode, color...',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF64748B)),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                              _applyFilters();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                    _applyFilters();
                  },
                ),
                const SizedBox(height: 16),

                // RangeSlider Filtering Details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filter by Stock Range',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_minStockFilter.toInt()} to ${_maxStockFilter.toInt()}',
                        style: const TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // RangeSlider Component
                RangeSlider(
                  values: RangeValues(_minStockFilter, _maxStockFilter),
                  min: 0.0,
                  max: _absoluteMaxStock > 0.0 ? _absoluteMaxStock : 1.0,
                  divisions: _absoluteMaxStock > 0 ? _absoluteMaxStock.toInt() : 1,
                  activeColor: primaryColor,
                  inactiveColor: const Color(0xFFE2E8F0),
                  labels: RangeLabels(
                    _minStockFilter.toInt().toString(),
                    _maxStockFilter.toInt().toString(),
                  ),
                  onChanged: (RangeValues values) {
                    setState(() {
                      _minStockFilter = values.start;
                      _maxStockFilter = values.end;
                    });
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),

          // 2. Stock Items List View
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  )
                : _filteredStock.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No matching stock items',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try refining your search terms or range slider constraints.'
                                    : 'There is no cached stock data matching the selected range.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAndRefreshStock,
                        color: primaryColor,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16.0),
                          itemCount: _filteredStock.length,
                          itemBuilder: (context, index) {
                            final item = _filteredStock[index];
                            final rawStock = item['stock'];
                            int stockQty = 0;
                            if (rawStock is num) {
                              stockQty = rawStock.toInt();
                            } else if (rawStock is String) {
                              stockQty = int.tryParse(rawStock) ?? 0;
                            }
                            final String mainBarcode = item['fair_barcode_main']?.toString() ?? 'N/A';
                            final String barcode = item['fair_barcode']?.toString() ?? 'N/A';
                            
                            final rawMrp = item['fair_mrp'];
                            double mrp = 0.0;
                            if (rawMrp is num) {
                              mrp = rawMrp.toDouble();
                            } else if (rawMrp is String) {
                              mrp = double.tryParse(rawMrp) ?? 0.0;
                            }
                            final String colour = item['fair_colour']?.toString() ?? 'N/A';
                            final String dressType = item['fair_dress_type']?.toString() ?? 'N/A';

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1.0,
                                ),
                              ),
                              color: Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Row 1: Style & Stock Capsule
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Style: $mainBarcode',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _getStockColor(stockQty).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$stockQty in Stock',
                                            style: TextStyle(
                                              color: _getStockColor(stockQty),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Divider(color: Color(0xFFF1F5F9)),
                                    const SizedBox(height: 8),

                                    // Row 2: Grid Details
                                    Row(
                                      children: [
                                        // Column 1
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _buildDetailText('Barcode', barcode),
                                              const SizedBox(height: 6),
                                              _buildDetailText('Color', colour),
                                            ],
                                          ),
                                        ),
                                        // Column 2
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _buildDetailText('Dress Type', dressType),
                                              const SizedBox(height: 6),
                                              _buildDetailText('MRP', '₹${mrp.toStringAsFixed(2)}'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailText(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }
}
