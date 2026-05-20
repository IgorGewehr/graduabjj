import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/upload_dto.dart' as api_upload;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../providers/selected_academy_provider.dart';
import '../../../services/services.dart';
import '../../../services/store_service.dart';
import '../../../widgets/cached_image.dart';

/// Product Form Bottom Sheet (create / edit)
class ProductFormSheet extends ConsumerStatefulWidget {
  final StoreProduct? product;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const ProductFormSheet({super.key, this.product, required this.onSave});

  @override
  ConsumerState<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _sizesController;
  late TextEditingController _colorsController;

  StoreProductCategory _category = StoreProductCategory.other;
  StoreStockType _stockType = StoreStockType.inStock;
  bool _isLoading = false;
  bool _isUploadingImage = false;
  List<String> _imageUrls = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name);
    _descriptionController = TextEditingController(
      text: widget.product?.description,
    );
    _priceController = TextEditingController(
      text: widget.product?.price.toStringAsFixed(2),
    );
    _stockController = TextEditingController(
      text: widget.product?.stockQuantity?.toString(),
    );
    _sizesController = TextEditingController(
      text: widget.product?.sizes?.join(', '),
    );
    _colorsController = TextEditingController(
      text: widget.product?.colors?.join(', '),
    );

    if (widget.product != null) {
      _category = widget.product!.category;
      _stockType = widget.product!.stockType;
      _imageUrls = List<String>.from(widget.product!.imageUrls);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _sizesController.dispose();
    _colorsController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Crop to 1:1 aspect ratio
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar Imagem',
            toolbarColor: AppTheme.textPrimary,
            toolbarWidgetColor: Colors.white,
            statusBarColor: AppTheme.textPrimary,
            backgroundColor: AppTheme.background,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
            showCropGrid: true,
          ),
          IOSUiSettings(
            title: 'Recortar Imagem',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            minimumAspectRatio: 1.0,
          ),
        ],
      );

      if (croppedFile == null) return;

      setState(() => _isUploadingImage = true);

      final academyId = ref.read(safeAcademyIdProvider) ?? '';
      final file = File(croppedFile.path);

      // Upload via Tatami signed-URL (fallback Firebase Storage removido).
      final repo = ref.read(tatami_repos.uploadsRepoProvider);
      final uploaded = await repo.uploadFileFromDisk(
        purpose: api_upload.ApiUploadPurpose.storeProduct,
        file: file,
        contentType: 'image/jpeg',
        academyId: academyId,
      );
      final downloadUrl = uploaded.publicUrl;
      if (downloadUrl == null) {
        setState(() => _isUploadingImage = false);
        if (mounted) context.showError('Upload concluído sem URL pública.');
        return;
      }

      setState(() {
        _imageUrls.add(downloadUrl);
        _isUploadingImage = false;
      });
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        context.showError('Erro ao fazer upload: $e');
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final sizes = _sizesController.text.isNotEmpty
          ? _sizesController.text.split(',').map((s) => s.trim()).toList()
          : <String>[];
      final colors = _colorsController.text.isNotEmpty
          ? _colorsController.text.split(',').map((s) => s.trim()).toList()
          : <String>[];

      final data = {
        'name': _nameController.text,
        'description': _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        'price': double.parse(_priceController.text.replaceAll(',', '.')),
        'category': _category.value,
        'stockType': _stockType.value,
        'stockQuantity': _stockType == StoreStockType.inStock
            ? int.tryParse(_stockController.text) ?? 0
            : null,
        'sizes': sizes.isEmpty ? null : sizes,
        'colors': colors.isEmpty ? null : colors,
        'images': _imageUrls,
      };

      await widget.onSave(data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        context.showError('Erro ao salvar: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.product != null ? 'Editar Produto' : 'Novo Produto',
                      style: AppTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Images Section
                      Text('Fotos do Produto', style: AppTheme.labelMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 100,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // Existing images
                            ..._imageUrls.asMap().entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.divider,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: AppCachedImage(
                                        imageUrl: entry.value,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorIcon: const Icon(
                                          LucideIcons.imageOff,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _removeImage(entry.key),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            LucideIcons.x,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (entry.key == 0)
                                      Positioned(
                                        bottom: 4,
                                        left: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Principal',
                                            style: AppTheme.labelSmall.copyWith(
                                              color: Colors.white,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            // Add button
                            GestureDetector(
                              onTap: _isUploadingImage
                                  ? null
                                  : _pickAndUploadImage,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.divider,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: _isUploadingImage
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.imagePlus,
                                            color: AppTheme.textSecondary,
                                            size: 24,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Adicionar',
                                            style: AppTheme.labelSmall.copyWith(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Name
                      _ModernTextField(
                        controller: _nameController,
                        label: 'Nome do Produto',
                        validator: (v) =>
                            v?.isEmpty == true ? 'Campo obrigatorio' : null,
                      ),
                      const SizedBox(height: 16),
                      // Description
                      _ModernTextField(
                        controller: _descriptionController,
                        label: 'Descricao (opcional)',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      // Price
                      _ModernTextField(
                        controller: _priceController,
                        label: 'Preco (R\$)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v?.isEmpty == true) return 'Campo obrigatorio';
                          if (double.tryParse(v!.replaceAll(',', '.')) == null) {
                            return 'Valor invalido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Category
                      Text('Categoria', style: AppTheme.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: StoreProductCategory.values.map((cat) {
                          return ChoiceChip(
                            label: Text(cat.label),
                            selected: _category == cat,
                            onSelected: (selected) {
                              if (selected) setState(() => _category = cat);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Stock Type
                      Text('Tipo de Estoque', style: AppTheme.labelMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: StoreStockType.values.map((type) {
                          return ChoiceChip(
                            label: Text(type.label),
                            selected: _stockType == type,
                            onSelected: (selected) {
                              if (selected) setState(() => _stockType = type);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Stock Quantity
                      if (_stockType == StoreStockType.inStock)
                        _ModernTextField(
                          controller: _stockController,
                          label: 'Quantidade em Estoque',
                          keyboardType: TextInputType.number,
                        ),
                      const SizedBox(height: 16),
                      // Sizes
                      _ModernTextField(
                        controller: _sizesController,
                        label: 'Tamanhos (separados por virgula)',
                        hint: 'Ex: P, M, G, GG',
                      ),
                      const SizedBox(height: 16),
                      // Colors
                      _ModernTextField(
                        controller: _colorsController,
                        label: 'Cores (separadas por virgula)',
                        hint: 'Ex: Branco, Azul, Preto',
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.product != null ? 'Salvar' : 'Criar Produto',
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modern Text Field (private to this file)
class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _ModernTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelMedium),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.error),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}
