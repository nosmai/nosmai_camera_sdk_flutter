import 'package:flutter/material.dart';
import 'package:nosmai_camera_sdk/nosmai_camera_sdk.dart';

/// Example showing metadata-based filter categorization
class MetadataFilterExample extends StatefulWidget {
  const MetadataFilterExample({super.key});

  @override
  State<MetadataFilterExample> createState() => _MetadataFilterExampleState();
}

class _MetadataFilterExampleState extends State<MetadataFilterExample> {
  final _nosmai = NosmaiFlutter.instance;

  // Filter state management
  Map<NosmaiFilterCategory, List<NosmaiFilter>> _filtersByCategory = {};
  String _currentFilterName = 'None';
  bool _isLoading = false;

  // Filter categories for display
  static const Map<NosmaiFilterCategory, FilterCategoryConfig>
      _categoryConfigs = {
    NosmaiFilterCategory.beauty: FilterCategoryConfig(
      name: 'Beauty Filters',
      icon: Icons.face,
      color: Colors.pink,
    ),
    NosmaiFilterCategory.effect: FilterCategoryConfig(
      name: 'Creative Effects',
      icon: Icons.auto_awesome,
      color: Colors.purple,
    ),
    NosmaiFilterCategory.filter: FilterCategoryConfig(
      name: 'Standard Filters',
      icon: Icons.tune,
      color: Colors.blue,
    ),
    NosmaiFilterCategory.unknown: FilterCategoryConfig(
      name: 'Other Filters',
      icon: Icons.help_outline,
      color: Colors.grey,
    ),
  };

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  /// Load and organize filters from all sources
  ///
  /// This method fetches filters from both local and cloud sources,
  /// then organizes them by category based on their metadata.
  Future<void> _loadFilters() async {
    
    setState(() => _isLoading = true);

    try {
      final filters = await _nosmai.getFilters();
      final organized = _organizeFiltersByCategory(filters);

      setState(() {
        _filtersByCategory = organized;
        _isLoading = false;
      });

      _logFilterCounts(organized);
    } catch (e) {
      debugPrint('Error loading filters: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Organize filters by their category
  Map<NosmaiFilterCategory, List<NosmaiFilter>> _organizeFiltersByCategory(
    List<NosmaiFilter> filters,
  ) {
    final organized = <NosmaiFilterCategory, List<NosmaiFilter>>{};

    // Initialize empty lists for all categories
    for (final category in NosmaiFilterCategory.values) {
      organized[category] = [];
    }

    // Categorize filters
    for (final filter in filters) {
      organized[filter.filterCategory]!.add(filter);
    }

    return organized;
  }

  /// Log filter counts for debugging
  void _logFilterCounts(
      Map<NosmaiFilterCategory, List<NosmaiFilter>> organized) {
    debugPrint('📊 Filters loaded:');
    organized.forEach((category, filters) {
      debugPrint('  ${category.name}: ${filters.length} filters');
    });
  }

  /// Apply a filter with proper handling based on its type
  ///
  /// This method handles both local and cloud filters, downloads cloud filters
  /// if needed, and properly manages beauty vs. effect filter application.
  Future<void> _applyFilter(NosmaiFilter filter) async {
    try {
      final isBeautyFilter = await _nosmai.isBeautyFilterEnabled();

      debugPrint('🎨 Applying filter: ${filter.displayName}');
      debugPrint('   Is beauty filter: $isBeautyFilter');

      // For non-beauty filters, remove existing effects first
      if (!isBeautyFilter) {
        await _nosmai.removeAllFilters();
      }

      final filterPath = await _getFilterPath(filter);

      if (filterPath != null) {
        await _nosmai.applyFilter(filterPath);
        setState(() {
          _currentFilterName = filter.displayName;
        });
      }
    } catch (e) {
      debugPrint('Error applying filter: $e');
      _showErrorSnackBar('Failed to apply filter: $e');
    }
  }

  /// Get the path for a filter, downloading if necessary
  Future<String?> _getFilterPath(NosmaiFilter filter) async {
    if (filter.isLocalFilter) {
      return filter.path;
    } else if (filter.isCloudFilter) {
      if (filter.isDownloaded) {
        return filter.path;
      } else {
        // Need to download first
        _showDownloadingSnackBar(filter.displayName);
        await _nosmai.downloadCloudFilter(filter.id);
        return null; // Return null to indicate download is in progress
      }
    }
    return null;
  }

  /// Show downloading snackbar
  void _showDownloadingSnackBar(String filterName) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading $filterName...')),
      );
    }
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Build a filter chip widget for a specific filter
  Widget _buildFilterChip(NosmaiFilter filter) {
    final config = _categoryConfigs[filter.filterCategory] ??
        _categoryConfigs[NosmaiFilterCategory.unknown]!;

    return Padding(
      padding: const EdgeInsets.all(4),
      child: ActionChip(
        avatar: Icon(config.icon, color: config.color, size: 18),
        label: Text(filter.displayName),
        onPressed: () => _applyFilter(filter),
        backgroundColor: config.color.withOpacity( 0.1),
      ),
    );
  }

  /// Build a category section with filters
  Widget _buildCategorySection(NosmaiFilterCategory category) {
    final filters = _filtersByCategory[category] ?? [];
    final config = _categoryConfigs[category];

    if (filters.isEmpty || config == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategoryHeader(config, filters.length),
            const SizedBox(height: 8),
            Wrap(
              children:
                  filters.map((filter) => _buildFilterChip(filter)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build category header with title and count
  Widget _buildCategoryHeader(FilterCategoryConfig config, int count) {
    return Row(
      children: [
        Icon(config.icon, color: config.color),
        const SizedBox(width: 8),
        Text(
          config.name,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: config.color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: config.color.withOpacity( 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(fontSize: 12, color: config.color),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metadata-Based Filters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Current filter indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).primaryColor.withOpacity( 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera),
                const SizedBox(width: 8),
                Text(
                  'Current Filter: $_currentFilterName',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // Filter categories
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      // Clear filter button
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await _nosmai.removeAllFilters();
                            setState(() => _currentFilterName = 'None');
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear All Filters'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),

                      // Render all category sections
                      ..._categoryConfigs.keys.map(
                        (category) => _buildCategorySection(category),
                      ),

                      // Info card
                      Card(
                        margin: const EdgeInsets.all(8),
                        color: Colors.blue[50],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.info, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Metadata-Based System',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Filters are now categorized using metadata from their manifest files. '
                                'Beauty filters can be stacked, while other filters replace existing effects.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue[700]),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Configuration class for filter categories
class FilterCategoryConfig {
  final String name;
  final IconData icon;
  final Color color;

  const FilterCategoryConfig({
    required this.name,
    required this.icon,
    required this.color,
  });
}

// Example usage in main app
void main() {
  runApp(MaterialApp(
    title: 'Nosmai Filter Example',
    theme: ThemeData(
      primarySwatch: Colors.blue,
      useMaterial3: true,
    ),
    home: const MetadataFilterExample(),
  ));
}
