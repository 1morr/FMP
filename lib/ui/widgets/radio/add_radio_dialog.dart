import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../services/radio/radio_controller.dart';

/// 添加電台對話框
class AddRadioDialog extends ConsumerStatefulWidget {
  const AddRadioDialog({super.key});

  /// 顯示對話框
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const AddRadioDialog(),
    );
  }

  @override
  ConsumerState<AddRadioDialog> createState() => _AddRadioDialogState();
}

class _AddRadioDialogState extends ConsumerState<AddRadioDialog> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final controller = ref.read(radioControllerProvider.notifier);
      await controller.addStation(_urlController.text.trim());

      if (mounted) {
        ToastService.success(context, '电台添加成功');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('从 URL 导入'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '添加 Bilibili 直播间作为电台',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: '粘贴直播间链接',
                  prefixIcon: Icon(Icons.link),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入直播间 URL';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleAdd(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _handleAdd,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('添加'),
        ),
      ],
    );
  }
}
