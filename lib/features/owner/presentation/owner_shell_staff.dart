part of 'owner_shell.dart';

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.activeBusiness,
    required this.ownerBusinesses,
    required this.staffMembers,
    required this.joinRequests,
    required this.groupAuditEvents,
    required this.canManageStaff,
    required this.actionInProgress,
    required this.onCreateStaff,
    required this.onEditStaff,
    required this.onResetStaffPassword,
    required this.onDisableStaff,
    required this.onVoteOnJoinRequest,
  });

  final BusinessSummary activeBusiness;
  final List<BusinessSummary> ownerBusinesses;
  final List<StaffMemberSummary> staffMembers;
  final List<GroupJoinRequestSummary> joinRequests;
  final List<GroupAuditEventSummary> groupAuditEvents;
  final bool canManageStaff;
  final bool actionInProgress;
  final Future<void> Function()? onCreateStaff;
  final Future<void> Function(StaffMemberSummary staff)? onEditStaff;
  final Future<void> Function(StaffMemberSummary staff)? onResetStaffPassword;
  final Future<void> Function(StaffMemberSummary staff)? onDisableStaff;
  final Future<void> Function(
    GroupJoinRequestSummary request,
    List<BusinessSummary> ownerBusinesses,
  )?
  onVoteOnJoinRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          key: const ValueKey('owner-staff-section'),
          title: 'Staff accounts',
          subtitle:
              'Each staff account is locked to one business and managed by backend-owned auth flows.',
          trailing: FilledButton.icon(
            key: const ValueKey('owner-staff-create'),
            onPressed: canManageStaff && !actionInProgress
                ? onCreateStaff
                : null,
            icon: actionInProgress
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: Text(
              canManageStaff
                  ? 'Create for ${activeBusiness.name}'
                  : 'Owner sign-in required',
            ),
          ),
          child: Column(
            children: staffMembers
                .map(
                  (staff) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(staff.name),
                    subtitle: Text(
                      '${staff.roleLabel} • ${staff.businessName}\n${staff.username}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusPill(
                          label: staff.isActive ? 'Active' : 'Disabled',
                          backgroundColor: staff.isActive
                              ? const Color(0xFFE7F5EF)
                              : const Color(0xFFFDECEC),
                          foregroundColor: staff.isActive
                              ? const Color(0xFF1B7F5B)
                              : const Color(0xFFB23A48),
                        ),
                        if (canManageStaff) ...[
                          const SizedBox(width: 4),
                          PopupMenuButton<_StaffAccountAction>(
                            key: ValueKey(
                              'owner-staff-actions-${staff.username}',
                            ),
                            tooltip: 'Staff actions',
                            enabled: !actionInProgress,
                            onSelected: (action) async {
                              if (action == _StaffAccountAction.edit) {
                                await onEditStaff?.call(staff);
                                return;
                              }

                              if (action == _StaffAccountAction.resetPassword) {
                                if (staff.isActive) {
                                  await onResetStaffPassword?.call(staff);
                                }
                                return;
                              }

                              if (staff.isActive) {
                                await onDisableStaff?.call(staff);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<_StaffAccountAction>(
                                key: ValueKey(
                                  'owner-staff-edit-${staff.username}',
                                ),
                                value: _StaffAccountAction.edit,
                                child: const Text('Edit staff'),
                              ),
                              if (staff.isActive)
                                PopupMenuItem<_StaffAccountAction>(
                                  key: ValueKey(
                                    'owner-staff-reset-${staff.username}',
                                  ),
                                  value: _StaffAccountAction.resetPassword,
                                  child: const Text('Reset password'),
                                ),
                              if (staff.isActive)
                                PopupMenuItem<_StaffAccountAction>(
                                  key: ValueKey(
                                    'owner-staff-disable-${staff.username}',
                                  ),
                                  value: _StaffAccountAction.disable,
                                  child: const Text('Disable'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Group approvals',
          subtitle:
              'Closed-group trust is enforced through unanimous business-level approvals.',
          child: Column(
            children: joinRequests
                .map(
                  (request) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    isThreeLine: true,
                    title: Text(request.businessName),
                    subtitle: Text(
                      '${request.groupName}\n${request.status} • ${request.approvalsReceived}/${request.approvalsRequired}\nRequested ${request.requestedAtLabel}',
                    ),
                    trailing:
                        request.statusCode == 'pending' &&
                            canManageStaff &&
                            onVoteOnJoinRequest != null
                        ? OutlinedButton(
                            onPressed: actionInProgress
                                ? null
                                : () => onVoteOnJoinRequest!(
                                    request,
                                    ownerBusinesses,
                                  ),
                            child: const Text('Vote'),
                          )
                        : null,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('owner-group-audit-section'),
          title: 'Tandem audit trail',
          subtitle:
              'Membership decisions stay traceable at the group level so approvals, rejections, and onboarding remain auditable.',
          child: groupAuditEvents.isEmpty
              ? const Text(
                  'Audit history will appear here once the tandem group records membership actions.',
                )
              : Column(
                  children: groupAuditEvents
                      .map(
                        (event) => ListTile(
                          key: ValueKey('owner-group-audit-event-${event.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: _auditBackgroundColor(
                              event.eventType,
                            ),
                            foregroundColor: _auditForegroundColor(
                              event.eventType,
                            ),
                            child: Icon(_auditIcon(event.eventType), size: 20),
                          ),
                          title: Text(event.title),
                          subtitle: Text(
                            '${event.detail}\n${event.groupName} • ${formatDateTime(event.occurredAt)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}
