part of 'owner_shell.dart';

class _BrandingDialog extends ConsumerStatefulWidget {
  const _BrandingDialog({required this.business});

  final BusinessSummary business;

  @override
  ConsumerState<_BrandingDialog> createState() => _BrandingDialogState();
}

class _BrandingDialogState extends ConsumerState<_BrandingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _logoUrlController;
  late final TextEditingController _coverImageUrlController;
  PickedBusinessAsset? _logoFile;
  PickedBusinessAsset? _coverFile;
  bool _logoPickerBusy = false;
  bool _coverPickerBusy = false;

  @override
  void initState() {
    super.initState();
    _logoUrlController = TextEditingController(text: widget.business.logoUrl);
    _coverImageUrlController = TextEditingController(
      text: widget.business.coverImageUrl,
    );
  }

  @override
  void dispose() {
    _logoUrlController.dispose();
    _coverImageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit branding for ${widget.business.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('owner-branding-logo-url-input'),
                  controller: _logoUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Logo image URL',
                    hintText: 'https://...',
                  ),
                  validator: _validateOptionalUrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('owner-branding-upload-logo'),
                      onPressed: _logoPickerBusy ? null : _pickLogoImage,
                      icon: _logoPickerBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _logoFile == null ? 'Upload logo' : 'Replace logo file',
                      ),
                    ),
                    if (_logoFile != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selected: ${_logoFile!.fileName}',
                          key: const ValueKey(
                            'owner-branding-logo-upload-name',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('owner-branding-cover-url-input'),
                  controller: _coverImageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Cover image URL',
                    hintText: 'https://...',
                  ),
                  validator: _validateOptionalUrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('owner-branding-upload-cover'),
                      onPressed: _coverPickerBusy ? null : _pickCoverImage,
                      icon: _coverPickerBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _coverFile == null
                            ? 'Upload cover'
                            : 'Replace cover file',
                      ),
                    ),
                    if (_coverFile != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selected: ${_coverFile!.fileName}',
                          key: const ValueKey(
                            'owner-branding-cover-upload-name',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'URLs still work as a fallback. If you upload a file here, it will go to Firebase Storage and the business profile will keep the storage path for future replacements.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF52606D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'If Storage has not been initialized in Firebase Console yet, upload will fail fast with a clear setup message instead of hanging.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-branding-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _BrandingPayload(
                logoUrl: _logoUrlController.text.trim(),
                coverImageUrl: _coverImageUrlController.text.trim(),
                logoFile: _logoFile,
                coverFile: _coverFile,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickLogoImage() async {
    await _pickImage(isLogo: true, dialogTitle: 'Choose logo image');
  }

  Future<void> _pickCoverImage() async {
    await _pickImage(isLogo: false, dialogTitle: 'Choose cover image');
  }

  Future<void> _pickImage({
    required bool isLogo,
    required String dialogTitle,
  }) async {
    setState(() {
      if (isLogo) {
        _logoPickerBusy = true;
      } else {
        _coverPickerBusy = true;
      }
    });

    try {
      final picked = await ref
          .read(businessAssetPickerProvider)
          .pickImage(dialogTitle: dialogTitle);
      if (!mounted || picked == null) {
        return;
      }

      setState(() {
        if (isLogo) {
          _logoFile = picked;
        } else {
          _coverFile = picked;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          if (isLogo) {
            _logoPickerBusy = false;
          } else {
            _coverPickerBusy = false;
          }
        });
      }
    }
  }

  String? _validateOptionalUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Use a valid http or https URL.';
    }
    return null;
  }
}

class _MediaDialog extends ConsumerStatefulWidget {
  const _MediaDialog({required this.businessName, this.initial});

  final String businessName;
  final BusinessMediaSummary? initial;

  @override
  ConsumerState<_MediaDialog> createState() => _MediaDialogState();
}

class _MediaDialogState extends ConsumerState<_MediaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _captionController;
  late final TextEditingController _imageUrlController;
  late String _mediaType;
  late bool _isFeatured;
  PickedBusinessAsset? _imageFile;
  bool _pickerBusy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _captionController = TextEditingController(text: initial?.caption ?? '');
    _imageUrlController = TextEditingController(text: initial?.imageUrl ?? '');
    _mediaType = initial?.mediaType ?? 'gallery';
    _isFeatured = initial?.isFeatured ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _captionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit media item' : 'Add media item'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This media entry belongs to ${widget.businessName}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('owner-media-title-input'),
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mediaType,
                  decoration: const InputDecoration(labelText: 'Media type'),
                  items: const [
                    DropdownMenuItem(value: 'gallery', child: Text('Gallery')),
                    DropdownMenuItem(
                      value: 'menu',
                      child: Text('Menu highlight'),
                    ),
                    DropdownMenuItem(
                      value: 'portfolio',
                      child: Text('Portfolio'),
                    ),
                    DropdownMenuItem(
                      value: 'storefront',
                      child: Text('Storefront'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _mediaType = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('owner-media-image-url-input'),
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'https://...',
                  ),
                  validator: _validateMediaImageSource,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('owner-media-upload-image'),
                      onPressed: _pickerBusy ? null : _pickImage,
                      icon: _pickerBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _imageFile == null ? 'Upload image' : 'Replace image',
                      ),
                    ),
                    if (_imageFile != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selected: ${_imageFile!.fileName}',
                          key: const ValueKey('owner-media-upload-name'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Use either a direct URL or a Storage upload. Upload needs Firebase Storage to be initialized for this project.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('owner-media-caption-input'),
                  controller: _captionController,
                  decoration: const InputDecoration(
                    labelText: 'Caption',
                    hintText:
                        'Seasonal menu, signature service, inside view...',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Featured media'),
                  subtitle: const Text(
                    'Featured items stay pinned higher in the gallery section.',
                  ),
                  value: _isFeatured,
                  onChanged: (value) {
                    setState(() {
                      _isFeatured = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-media-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _MediaPayload(
                title: _titleController.text.trim(),
                caption: _captionController.text.trim(),
                mediaType: _mediaType,
                imageUrl: _imageUrlController.text.trim(),
                isFeatured: _isFeatured,
                imageFile: _imageFile,
              ),
            );
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  Future<void> _pickImage() async {
    setState(() {
      _pickerBusy = true;
    });

    try {
      final picked = await ref
          .read(businessAssetPickerProvider)
          .pickImage(dialogTitle: 'Choose gallery image');
      if (!mounted || picked == null) {
        return;
      }

      setState(() {
        _imageFile = picked;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _pickerBusy = false;
        });
      }
    }
  }

  String? _validateMediaImageSource(String? value) {
    if (_imageFile != null) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return 'Provide an image URL or upload a file.';
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Use a valid http or https URL.';
    }
    return null;
  }
}

class _BusinessLocationDialog extends StatefulWidget {
  const _BusinessLocationDialog({required this.businessName, this.initial});

  final String businessName;
  final BusinessLocationSummary? initial;

  @override
  State<_BusinessLocationDialog> createState() =>
      _BusinessLocationDialogState();
}

class _BusinessLocationDialogState extends State<_BusinessLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _workingHoursController;
  late final TextEditingController _phoneNumbersController;
  late final TextEditingController _notesController;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _addressController = TextEditingController(text: initial?.address ?? '');
    _workingHoursController = TextEditingController(
      text: initial?.workingHours ?? '',
    );
    _phoneNumbersController = TextEditingController(
      text: initial?.phoneNumbers.join(', ') ?? '',
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _isPrimary = initial?.isPrimary ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _phoneNumbersController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit location' : 'Add location'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This location belongs to ${widget.businessName}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Location name',
                    hintText: 'Old Town branch',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workingHoursController,
                  decoration: const InputDecoration(labelText: 'Working hours'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumbersController,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText: '+998712000111, +998901234567',
                  ),
                  validator: (value) {
                    final phoneNumbers = _parsePhoneNumbers(value);
                    if (phoneNumbers.isEmpty) {
                      return 'Enter at least one phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Location notes',
                    hintText:
                        'Second floor, takeaway counter, parking available',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primary location'),
                  subtitle: const Text(
                    'Use this for the main branch highlighted in the business profile.',
                  ),
                  value: _isPrimary,
                  onChanged: (value) {
                    setState(() {
                      _isPrimary = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _LocationPayload(
                name: _nameController.text.trim(),
                address: _addressController.text.trim(),
                workingHours: _workingHoursController.text.trim(),
                phoneNumbers: _parsePhoneNumbers(_phoneNumbersController.text),
                notes: _notesController.text.trim(),
                isPrimary: _isPrimary,
              ),
            );
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  List<String> _parsePhoneNumbers(String? value) {
    return (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _CatalogItemDialog extends StatefulWidget {
  const _CatalogItemDialog({
    required this.title,
    required this.itemTypeLabel,
    this.initial,
  });

  final String title;
  final String itemTypeLabel;
  final BusinessCatalogItemSummary? initial;

  @override
  State<_CatalogItemDialog> createState() => _CatalogItemDialogState();
}

class _CatalogItemDialogState extends State<_CatalogItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceLabelController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _priceLabelController = TextEditingController(
      text: initial?.priceLabel ?? '',
    );
    _isActive = initial?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '${widget.itemTypeLabel} name',
                    hintText: widget.itemTypeLabel == 'product'
                        ? 'Signature breakfast set'
                        : 'Private tasting session',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: '${widget.itemTypeLabel} description',
                  ),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Price label',
                    hintText: '55 000 UZS / from 90 000 UZS / seasonal',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible in catalog'),
                  subtitle: const Text(
                    'Paused items stay in Firestore but are clearly marked in the owner view.',
                  ),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CatalogItemPayload(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                priceLabel: _priceLabelController.text.trim(),
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _CreateBusinessDialog extends StatefulWidget {
  const _CreateBusinessDialog();

  @override
  State<_CreateBusinessDialog> createState() => _CreateBusinessDialogState();
}

class _CreateBusinessDialogState extends State<_CreateBusinessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _phoneNumbersController = TextEditingController();
  final _cashbackController = TextEditingController(text: '500');
  final _redeemPolicyController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _phoneNumbersController.dispose();
    _cashbackController.dispose();
    _redeemPolicyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create business'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Business name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workingHoursController,
                  decoration: const InputDecoration(labelText: 'Working hours'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumbersController,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText: '+998712000111, +998901234567',
                  ),
                  validator: (value) {
                    final phoneNumbers = _parsePhoneNumbers(value);
                    if (phoneNumbers.isEmpty) {
                      return 'Enter at least one phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cashbackController,
                  decoration: const InputDecoration(
                    labelText: 'Cashback basis points',
                    hintText: '500',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed < 0 || parsed > 10000) {
                      return 'Use a whole number between 0 and 10000.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _redeemPolicyController,
                  decoration: const InputDecoration(labelText: 'Redeem policy'),
                  minLines: 2,
                  maxLines: 4,
                  validator: _required,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CreateBusinessPayload(
                name: _nameController.text.trim(),
                category: _categoryController.text.trim(),
                description: _descriptionController.text.trim(),
                address: _addressController.text.trim(),
                workingHours: _workingHoursController.text.trim(),
                phoneNumbers: _parsePhoneNumbers(_phoneNumbersController.text),
                cashbackBasisPoints: int.parse(_cashbackController.text.trim()),
                redeemPolicy: _redeemPolicyController.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  List<String> _parsePhoneNumbers(String? value) {
    return (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _CreateTandemGroupDialog extends StatefulWidget {
  const _CreateTandemGroupDialog({required this.businessName});

  final String businessName;

  @override
  State<_CreateTandemGroupDialog> createState() =>
      _CreateTandemGroupDialogState();
}

class _CreateTandemGroupDialogState extends State<_CreateTandemGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.businessName} Circle',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Create tandem group for ${widget.businessName}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Group name'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Group name is required.';
              }
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(_nameController.text.trim());
          },
          child: const Text('Create group'),
        ),
      ],
    );
  }
}

class _RequestJoinGroupDialog extends StatefulWidget {
  const _RequestJoinGroupDialog({required this.business, required this.groups});

  final BusinessSummary business;
  final List<JoinableGroupOption> groups;

  @override
  State<_RequestJoinGroupDialog> createState() =>
      _RequestJoinGroupDialogState();
}

class _RequestJoinGroupDialogState extends State<_RequestJoinGroupDialog> {
  late String _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.groups.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Request ${widget.business.name} to join a group'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Every active member business in the selected group must approve this request.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              decoration: const InputDecoration(labelText: 'Target group'),
              items: widget.groups
                  .map(
                    (group) => DropdownMenuItem<String>(
                      value: group.id,
                      child: Text(
                        '${group.name} (${group.activeBusinessCount} active)',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedGroupId = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final selectedGroup = widget.groups.firstWhere(
              (group) => group.id == _selectedGroupId,
            );
            Navigator.of(context).pop(
              _RequestJoinGroupPayload(
                groupId: selectedGroup.id,
                groupName: selectedGroup.name,
              ),
            );
          },
          child: const Text('Request join'),
        ),
      ],
    );
  }
}

class _EditBusinessDialog extends StatefulWidget {
  const _EditBusinessDialog({required this.business});

  final BusinessSummary business;

  @override
  State<_EditBusinessDialog> createState() => _EditBusinessDialogState();
}

class _EditBusinessDialogState extends State<_EditBusinessDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _addressController;
  late final TextEditingController _workingHoursController;
  late final TextEditingController _phoneNumbersController;
  late final TextEditingController _cashbackController;
  late final TextEditingController _redeemPolicyController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.business.name);
    _categoryController = TextEditingController(text: widget.business.category);
    _descriptionController = TextEditingController(
      text: widget.business.description,
    );
    _addressController = TextEditingController(text: widget.business.address);
    _workingHoursController = TextEditingController(
      text: widget.business.workingHours,
    );
    _phoneNumbersController = TextEditingController(
      text: widget.business.phoneNumbers.join(', '),
    );
    _cashbackController = TextEditingController(
      text: widget.business.cashbackBasisPoints.toString(),
    );
    _redeemPolicyController = TextEditingController(
      text: widget.business.redeemPolicy,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _phoneNumbersController.dispose();
    _cashbackController.dispose();
    _redeemPolicyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.business.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Business name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workingHoursController,
                  decoration: const InputDecoration(labelText: 'Working hours'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumbersController,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText: '+998712000111, +998901234567',
                  ),
                  validator: (value) {
                    final phoneNumbers = _parsePhoneNumbers(value);
                    if (phoneNumbers.isEmpty) {
                      return 'Enter at least one phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cashbackController,
                  decoration: const InputDecoration(
                    labelText: 'Cashback basis points',
                    hintText: '700',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed < 0 || parsed > 10000) {
                      return 'Use a whole number between 0 and 10000.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _redeemPolicyController,
                  decoration: const InputDecoration(labelText: 'Redeem policy'),
                  minLines: 2,
                  maxLines: 4,
                  validator: _required,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _EditBusinessPayload(
                name: _nameController.text.trim(),
                category: _categoryController.text.trim(),
                description: _descriptionController.text.trim(),
                address: _addressController.text.trim(),
                workingHours: _workingHoursController.text.trim(),
                phoneNumbers: _parsePhoneNumbers(_phoneNumbersController.text),
                cashbackBasisPoints: int.parse(_cashbackController.text.trim()),
                redeemPolicy: _redeemPolicyController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  List<String> _parsePhoneNumbers(String? value) {
    return (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _VoteOnJoinRequestPayload {
  const _VoteOnJoinRequestPayload({
    required this.voterBusinessId,
    required this.voterBusinessName,
    required this.vote,
  });

  final String voterBusinessId;
  final String voterBusinessName;
  final String vote;
}

class _VoteOnJoinRequestDialog extends StatefulWidget {
  const _VoteOnJoinRequestDialog({
    required this.request,
    required this.eligibleBusinesses,
  });

  final GroupJoinRequestSummary request;
  final List<BusinessSummary> eligibleBusinesses;

  @override
  State<_VoteOnJoinRequestDialog> createState() =>
      _VoteOnJoinRequestDialogState();
}

class _VoteOnJoinRequestDialogState extends State<_VoteOnJoinRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedBusinessId;
  String _selectedVote = 'yes';

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.eligibleBusinesses.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Vote on ${widget.request.businessName}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each active member business must vote separately before the join request can be approved.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedBusinessId,
                decoration: const InputDecoration(labelText: 'Voting business'),
                items: widget.eligibleBusinesses
                    .map(
                      (business) => DropdownMenuItem<String>(
                        value: business.id,
                        child: Text(business.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _selectedBusinessId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'yes',
                    label: Text('Approve'),
                    icon: Icon(Icons.thumb_up_alt_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'no',
                    label: Text('Reject'),
                    icon: Icon(Icons.thumb_down_alt_outlined),
                  ),
                ],
                selected: {_selectedVote},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedVote = selection.first;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            final selectedBusiness = widget.eligibleBusinesses.firstWhere(
              (business) => business.id == _selectedBusinessId,
            );

            Navigator.of(context).pop(
              _VoteOnJoinRequestPayload(
                voterBusinessId: selectedBusiness.id,
                voterBusinessName: selectedBusiness.name,
                vote: _selectedVote,
              ),
            );
          },
          child: Text(_selectedVote == 'yes' ? 'Approve' : 'Reject'),
        ),
      ],
    );
  }
}

class _AdminAdjustmentPayload {
  const _AdminAdjustmentPayload({
    required this.customerPhoneE164,
    required this.amountMinorUnits,
    required this.note,
    required this.direction,
  });

  final String customerPhoneE164;
  final int amountMinorUnits;
  final String note;
  final _AdjustmentDirection direction;
}

class _RefundCashbackPayload {
  const _RefundCashbackPayload({required this.redemptionBatchId, this.note});

  final String redemptionBatchId;
  final String? note;
}

class _ExpireWalletLotsPayload {
  const _ExpireWalletLotsPayload({this.maxLots});

  final int? maxLots;
}
