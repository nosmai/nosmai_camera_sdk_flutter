import 'package:flutter/material.dart';
import 'package:nosmai_camera_sdk/nosmai_flutter.dart';

/// Example showing metadata-based filter categorization
class MetadataFilterExample extends StatefulWidget {
  const MetadataFilterExample({super.key});

  @override
  State<MetadataFilterExample> createState() => _MetadataFilterExampleState();
}

class _MetadataFilterExampleState extends State<MetadataFilterExample> {
  final _nosmai = NosmaiFlutter.instance;
  Map<NosmaiFilterCategory, List<NosmaiFilter>> _filtersByCategory = {};
  String _currentFilterName = 'None';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    setState(() => _isLoading = true);

    try {
      // Load filters from all sources
      final filters = await _nosmai.fetchFiltersAndEffectsFromAllSources();
      
      // Organize filters by category
      final organized = <NosmaiFilterCategory, List<NosmaiFilter>>{};
      for (final category in NosmaiFilterCategory.values) {
        organized[category] = [];
      }
      
      for (final filter in filters) {
        organized[filter.filterCategory]!.add(filter);
      }

      setState(() {
        _filtersByCategory = organized;
        _isLoading = false;
      });

      // Log filter counts
      debugPrint('📊 Filters loaded:');
      organized.forEach((category, filters) {
        debugPrint('  ${category.name}: ${filters.length} filters');
      });
    } catch (e) {
      debugPrint('Error loading filters: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _applyFilter(NosmaiFilter filter) async {
    // Determine if this is a beauty filter using metadata
    final isBeautyFilter = await _nosmai.isBeautyFilter();

    debugPrint('🎨 Applying filter: ${filter.displayName}');
    debugPrint('   Is beauty filter: $isBeautyFilter');

    try {
      // For non-beauty filters, remove existing effects first
      if (!isBeautyFilter) {
        await _nosmai.removeAllFilters();
      }

      // Apply the filter
      String? filterPath;
      String displayName = '';

      if (filter.isLocalFilter) {
        filterPath = filter.path;
        displayName = filter.displayName;
      } else if (filter.isCloudFilter) {
        if (filter.isDownloaded) {
          filterPath = filter.path;
          displayName = filter.displayName;
        } else {
          // Need to download first
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloading ${filter.displayName}...')),
            );
          }
          await _nosmai.downloadCloudFilter(filter.id);
          return;
        }
      }

      if (filterPath != null) {
        await _nosmai.applyEffect(filterPath);
        setState(() {
          _currentFilterName = displayName;
        });
      }
    } catch (e) {
      debugPrint('Error applying filter: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply filter: $e')),
        );
      }
    }
  }

  Widget _buildFilterChip(NosmaiFilter filter) {
    final displayName = filter.displayName;
    final category = filter.filterCategory;

    // Choose icon based on category
    IconData icon;
    Color color;

    switch (category) {
      case NosmaiFilterCategory.beauty:
        icon = Icons.face;
        color = Colors.pink;
        break;
      case NosmaiFilterCategory.effect:
        icon = Icons.auto_awesome;
        color = Colors.purple;
        break;
      case NosmaiFilterCategory.filter:
        icon = Icons.tune;
        color = Colors.blue;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: ActionChip(
        avatar: Icon(icon, color: color, size: 18),
        label: Text(displayName),
        onPressed: () => _applyFilter(filter),
        backgroundColor: color.withValues(alpha: 0.1),
      ),
    );
  }

  Widget _buildCategorySection(
    String title,
    NosmaiFilterCategory category,
    IconData icon,
    Color color,
  ) {
    final filters = _filtersByCategory[category] ?? [];

    if (filters.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${filters.length}',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
              ],
            ),
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
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
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

                      // Beauty filters section
                      _buildCategorySection(
                        'Beauty Filters',
                        NosmaiFilterCategory.beauty,
                        Icons.face,
                        Colors.pink,
                      ),

                      // Effect filters section
                      _buildCategorySection(
                        'Creative Effects',
                        NosmaiFilterCategory.effect,
                        Icons.auto_awesome,
                        Colors.purple,
                      ),

                      // Standard filters section
                      _buildCategorySection(
                        'Standard Filters',
                        NosmaiFilterCategory.filter,
                        Icons.tune,
                        Colors.blue,
                      ),

                      // Unknown filters section (if any)
                      _buildCategorySection(
                        'Other Filters',
                        NosmaiFilterCategory.unknown,
                        Icons.help_outline,
                        Colors.grey,
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
