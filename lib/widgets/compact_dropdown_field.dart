import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// An anchored selection menu with a bounded, scrollable options list.
class CompactDropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String>? validator;

  const CompactDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final menuWidth = constraints.maxWidth.clamp(0.0, 280.0);
      return DropdownMenuFormField<String>(
        width: constraints.maxWidth,
        initialSelection: value,
        label: Text(label),
        selectOnly: true,
        requestFocusOnTap: false,
        enableSearch: false,
        textStyle: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        menuStyle: MenuStyle(
          alignment: Alignment.bottomLeft,
          maximumSize: WidgetStatePropertyAll(Size(menuWidth, 240)),
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding:
              const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.divider),
          )),
        ),
        alignmentOffset: const Offset(0, 4),
        dropdownMenuEntries: options
            .map((option) => DropdownMenuEntry<String>(
                  value: option,
                  label: option,
                  style: MenuItemButton.styleFrom(
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 48),
                  ),
                ))
            .toList(),
        validator: validator,
        onSelected: onChanged,
      );
    });
  }
}
