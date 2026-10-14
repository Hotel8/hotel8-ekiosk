// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Walk-In Search.
///
/// Search for available rooms without a reservation. Shows available
/// rooms with rates, floor plan view, and room selection.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../bff_client.dart';
import '../models.dart';

class WalkInSearchPage extends StatefulWidget {
  const WalkInSearchPage({super.key, required this.client, required this.propertyId});

  final BffClient client;

  /// Property the terminal serves (from the App runtime context).
  final String propertyId;

  @override
  State<WalkInSearchPage> createState() => _WalkInSearchPageState();
}

class _WalkInSearchPageState extends State<WalkInSearchPage> {
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _guests = 1;
  int _rooms = 1;
  bool _searching = false;
  List<WalkInRoom> _results = const [];
  WalkInRoom? _selected;
  bool _showFloorPlan = false;

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _results = const [];
      _selected = null;
    });
    try {
      final rooms = await widget.client.searchWalkInAvailability(
        widget.propertyId,
        WalkInSearch(
          arrivalDate: _checkIn,
          departureDate: _checkOut,
          numberOfGuests: _guests,
          numberOfRooms: _rooms,
        ),
      );
      if (mounted) setState(() => _results = rooms);
    } on BffException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickCheckIn() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _checkIn,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    setState(() {
      _checkIn = date;
      if (_checkOut.isBefore(date.add(const Duration(days: 1)))) {
        _checkOut = date.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickCheckOut() async {
    final first = _checkIn.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: _checkOut,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    setState(() => _checkOut = date);
  }

  Future<void> _confirmSelection() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room.')),
      );
      return;
    }
    final room = _selected!;
    setState(() => null);
    try {
      // Express booking (ekiosk/DESIGN.md §4 Walk-in booking): the PMS
      // walk-in surface creates the CONFIRMED reservation; the wizard then
      // check-ins it via the normal route (payment rides the stay's folio).
      final reservation = await widget.client.createWalkInBooking(
        propertyId: widget.propertyId,
        roomTypeId: room.roomTypeId,
        arrivalDate: _checkIn,
        departureDate: _checkOut,
        lastName: 'Walk-in',
      );
      if (!mounted) return;
      Navigator.pop(context, reservation);
    } on BffException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walk-In Availability'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Check In',
                            value: fmt.format(_checkIn),
                            onTap: _pickCheckIn,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _DateField(
                            label: 'Check Out',
                            value: fmt.format(_checkOut),
                            onTap: _pickCheckOut,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _CounterField(
                            label: 'Guests',
                            value: _guests,
                            onChanged: (v) => setState(() => _guests = v),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _CounterField(
                            label: 'Rooms',
                            value: _rooms,
                            onChanged: (v) => setState(() => _rooms = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _searching ? null : _search,
                        icon: _searching
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.search),
                        label: Text(_searching ? 'Searching...' : 'Search Rooms'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Results
          Expanded(
            child: _results.isEmpty && !_searching
                ? _EmptyResults()
                : _searching
                    ? const Center(child: CircularProgressIndicator())
                    : _showFloorPlan
                        ? _FloorPlanView(
                            rooms: _results,
                            selected: _selected,
                            onSelected: (room) =>
                                setState(() => _selected = room),
                          )
                        : _RoomListView(
                            rooms: _results,
                            selected: _selected,
                            onSelected: (room) =>
                                setState(() => _selected = room),
                          ),
          ),
          // Toggle and confirm
          if (_results.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => setState(
                          () => _showFloorPlan = !_showFloorPlan),
                      icon: Icon(_showFloorPlan ? Icons.list : Icons.map),
                      label: Text(
                          _showFloorPlan ? 'List View' : 'Floor Plan View'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _selected == null ? null : _confirmSelection,
                      icon: const Icon(Icons.check),
                      label: const Text('Continue'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
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
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(value, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

class _CounterField extends StatelessWidget {
  const _CounterField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('$label:', style: const TextStyle(fontSize: 16)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            iconSize: 32,
          ),
          Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 9 ? () => onChanged(value + 1) : null,
            iconSize: 32,
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('Search for Available Rooms',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 18)),
        ],
      ),
    );
  }
}

class _RoomListView extends StatelessWidget {
  const _RoomListView({
    required this.rooms,
    required this.selected,
    required this.onSelected,
  });
  final List<WalkInRoom> rooms;
  final WalkInRoom? selected;
  final ValueChanged<WalkInRoom> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final room = rooms[i];
        final isSelected = selected?.roomNumber == room.roomNumber;
        return Card(
          elevation: 2,
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          child: InkWell(
            onTap: room.available ? () => onSelected(room) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    room.available ? Icons.meeting_room : Icons.do_not_disturb,
                    size: 48,
                    color: room.available
                        ? (isSelected ? Theme.of(context).colorScheme.primary : Colors.green)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Room ${room.roomNumber}',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        Text('${room.roomTypeName} • Floor ${room.floorNumber}',
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
                        if (room.features.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 4,
                              children: room.features
                                  .map((f) => Chip(
                                        label: Text(f),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        labelStyle: const TextStyle(fontSize: 12),
                                      ))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${room.currencyCode} ${room.ratePerNight.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text('/night', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FloorPlanView extends StatelessWidget {
  const _FloorPlanView({
    required this.rooms,
    required this.selected,
    required this.onSelected,
  });
  final List<WalkInRoom> rooms;
  final WalkInRoom? selected;
  final ValueChanged<WalkInRoom> onSelected;

  @override
  Widget build(BuildContext context) {
    // Group by floor
    final floors = <String, List<WalkInRoom>>{};
    for (final room in rooms) {
      floors.putIfAbsent(room.floorNumber, () => []).add(room);
    }
    final sortedFloors = floors.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: sortedFloors.reversed.map((floor) {
        final floorRooms = floors[floor]!;
        return Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Floor $floor',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: floorRooms.map((room) {
                    final isSelected = selected?.roomNumber == room.roomNumber;
                    final isAvailable = room.available;
                    return GestureDetector(
                      onTap: isAvailable ? () => onSelected(room) : null,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          border: Border.all(
                            width: isSelected ? 3 : 1,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : isAvailable
                                    ? Colors.green
                                    : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                              : isAvailable
                                  ? Colors.green.withValues(alpha: 0.05)
                                  : Colors.grey.shade100,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(room.roomNumber,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isAvailable
                                        ? Colors.black87
                                        : Colors.grey)),
                            Text(
                              '${room.currencyCode}${room.ratePerNight.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}