import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/log_entry.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<LogEntry> _entries = [];
  bool _loading = true;
  LogLevel? _filterLevel;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final entries = await AppDi.logs.recent(limit: AppConstants.maxLogEntries);
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  List<LogEntry> get _filtered => _filterLevel == null
      ? _entries
      : _entries.where((e) => e.level == _filterLevel).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LockAllButton(),
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        title: const Text('Logs'),
        actions: [
          PopupMenuButton<LogLevel?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onSelected: (v) => setState(() => _filterLevel = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              ...LogLevel.values.map((l) => PopupMenuItem(
                    value: l,
                    child: Text(l.name.toUpperCase()),
                  )),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear',
            onPressed: () async {
              await AppDi.logs.clear();
              _loadLogs();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(
                  child: Text(
                    'No logs',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final e = _filtered[i];
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: _levelColor(e.level),
                            width: 3,
                          ),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        minVerticalPadding: 2,
                        leading: Text(
                          e.level.name.toUpperCase(),
                          style: TextStyle(
                            color: _levelColor(e.level),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        title: Text(
                          e.message,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${e.tag} · ${fmt.format(e.createdAt.toLocal())}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.amber;
      case LogLevel.error:
        return Colors.red;
    }
  }
}
