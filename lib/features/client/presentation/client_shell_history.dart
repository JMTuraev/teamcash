part of 'client_shell.dart';

enum _ClientHistoryFilter { all, incoming, outgoing, transfers, checkouts }

class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.events});

  final List<WalletEvent> events;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  _ClientHistoryFilter _selectedFilter = _ClientHistoryFilter.all;
  final _searchController = TextEditingController();
  final PageController _pageController = PageController(viewportFraction: 0.96);
  int _activePage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents =
        widget.events
            .where((event) => _matchesHistoryFilter(event, _selectedFilter))
            .where((event) => _matchesHistorySearch(event, ''))
            .toList()
          ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final groupedEvents = _groupEventsByDay(filteredEvents);

    if (_activePage >= filteredEvents.length && filteredEvents.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _pageController.jumpToPage(0);
        setState(() {
          _activePage = 0;
        });
      });
    }

    if (context.mounted) {
      return SizedBox.expand(
        child: SectionCard(
          key: const ValueKey('client-history-tab'),
          title: 'Activity',
          subtitle:
              'Critical UX fix: history is now paged into digest cards instead of an endless ledger feed.',
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ClientHistoryFilter.values
                    .map(
                      (filter) => ChoiceChip(
                        key: ValueKey('client-history-filter-${filter.name}'),
                        label: Text(_labelForHistoryFilter(filter)),
                        selected: filter == _selectedFilter,
                        onSelected: (_) {
                          setState(() {
                            _selectedFilter = filter;
                            _activePage = 0;
                          });
                          _pageController.jumpToPage(0);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Showing ${filteredEvents.length} of ${widget.events.length} ledger events.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: filteredEvents.isEmpty
                    ? const Center(
                        child: ListTile(
                          key: ValueKey('client-history-empty-state'),
                          contentPadding: EdgeInsets.zero,
                          title: Text('No ledger events match this filter'),
                          subtitle: Text(
                            'Switch the chip above to inspect transfers, checkouts, or outgoing movement.',
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 282,
                            child: PageView.builder(
                              controller: _pageController,
                              onPageChanged: (index) {
                                setState(() {
                                  _activePage = index;
                                });
                              },
                              itemCount: filteredEvents.length,
                              itemBuilder: (context, index) => Padding(
                                padding: EdgeInsets.only(
                                  right: index == filteredEvents.length - 1
                                      ? 0
                                      : 8,
                                ),
                                child: _CompactHistoryEventCard(
                                  event: filteredEvents[index],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          PagerDots(
                            count: filteredEvents.length,
                            activeIndex: _activePage,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return SectionCard(
      key: const ValueKey('client-history-tab'),
      title: 'Ledger history',
      subtitle:
          'History is append-only and never disappears, even when ownership changes or gifts stay pending.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('client-history-search-input'),
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search history',
              hintText: 'Gift, Silk Road, checkout...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _ClientHistoryFilter.values
                .map(
                  (filter) => ChoiceChip(
                    key: ValueKey('client-history-filter-${filter.name}'),
                    label: Text(_labelForHistoryFilter(filter)),
                    selected: filter == _selectedFilter,
                    onSelected: (_) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Showing ${filteredEvents.length} of ${widget.events.length} ledger events.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 8),
          if (filteredEvents.isEmpty)
            const ListTile(
              key: ValueKey('client-history-empty-state'),
              contentPadding: EdgeInsets.zero,
              title: Text('No ledger events match this filter'),
              subtitle: Text(
                'Try another filter to inspect incoming, outgoing, transfer, or shared checkout activity.',
              ),
            ),
          ...groupedEvents.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF2455A6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...entry.value.map(
                    (event) => ListTile(
                      key: ValueKey('client-history-event-${event.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: event.isIncoming
                            ? const Color(0xFFE7F5EF)
                            : const Color(0xFFFFF2D8),
                        child: Icon(
                          event.isIncoming
                              ? Icons.south_west_outlined
                              : Icons.north_east_outlined,
                          color: event.isIncoming
                              ? const Color(0xFF1B7F5B)
                              : const Color(0xFF9C6100),
                        ),
                      ),
                      title: Text(event.title),
                      subtitle: Text(
                        '${event.subtitle}\n${event.issuerBusinessName} • ${formatDateTime(event.occurredAt)}',
                      ),
                      trailing: Text(
                        '${event.isIncoming ? '+' : '-'}${formatCurrency(event.amount)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesHistoryFilter(WalletEvent event, _ClientHistoryFilter filter) {
    switch (filter) {
      case _ClientHistoryFilter.all:
        return true;
      case _ClientHistoryFilter.incoming:
        return event.isIncoming;
      case _ClientHistoryFilter.outgoing:
        return !event.isIncoming;
      case _ClientHistoryFilter.transfers:
        return switch (event.type) {
          WalletEventType.transferOut ||
          WalletEventType.transferIn ||
          WalletEventType.giftPending ||
          WalletEventType.giftClaimed => true,
          _ => false,
        };
      case _ClientHistoryFilter.checkouts:
        return switch (event.type) {
          WalletEventType.sharedCheckoutCreated ||
          WalletEventType.sharedCheckoutContribution ||
          WalletEventType.sharedCheckoutFinalized => true,
          _ => false,
        };
    }
  }

  bool _matchesHistorySearch(WalletEvent event, String searchTerm) {
    if (searchTerm.isEmpty) {
      return true;
    }

    final haystack = [
      event.title,
      event.subtitle,
      event.groupName,
      event.issuerBusinessName,
    ].join(' ').toLowerCase();
    return haystack.contains(searchTerm);
  }

  String _labelForHistoryFilter(_ClientHistoryFilter filter) {
    return switch (filter) {
      _ClientHistoryFilter.all => 'All',
      _ClientHistoryFilter.incoming => 'Incoming',
      _ClientHistoryFilter.outgoing => 'Outgoing',
      _ClientHistoryFilter.transfers => 'Transfers',
      _ClientHistoryFilter.checkouts => 'Checkouts',
    };
  }

  Map<String, List<WalletEvent>> _groupEventsByDay(List<WalletEvent> events) {
    final grouped = <String, List<WalletEvent>>{};
    for (final event in events) {
      final key = formatShortDate(event.occurredAt);
      grouped.putIfAbsent(key, () => <WalletEvent>[]).add(event);
    }
    return grouped;
  }
}

class _CompactHistoryEventCard extends StatelessWidget {
  const _CompactHistoryEventCard({required this.event});

  final WalletEvent event;

  @override
  Widget build(BuildContext context) {
    final tint = event.isIncoming
        ? const Color(0xFF45C1B2)
        : const Color(0xFFFF8C6B);

    return Container(
      key: ValueKey('client-history-event-${event.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E8F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  event.isIncoming
                      ? Icons.south_west_outlined
                      : Icons.north_east_outlined,
                  color: tint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(event.occurredAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF52606D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${event.isIncoming ? '+' : '-'}${formatCurrency(event.amount)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _WalletFocusCard(
            title: event.groupName,
            headline: event.issuerBusinessName,
            supporting: event.subtitle,
            accent: tint,
          ),
        ],
      ),
    );
  }
}
