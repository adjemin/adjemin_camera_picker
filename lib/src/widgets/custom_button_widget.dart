import 'package:flutter/material.dart';

class CustomButtonWidget extends StatelessWidget {

  final double? width;
  final double? height;
  final String title;
  final Color? titleColor;
  final double? titleSize;
  final Color? color;
  final Function () onTap;
  const CustomButtonWidget({super.key,
    this.width,
    this.height,
    required this.title, this.titleColor,
    this.titleSize,
    this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return  GestureDetector(
      onTap: onTap,
      child: Container(
        width: width??MediaQuery.of(context).size.width,
        height: height??60,
        padding: const EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            top: 12,
            bottom: 12.0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color??Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(10)
        ),
        child: Text(title, style: TextStyle(
          color: titleColor??Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: titleSize??20
        ),),
      ),
    );
  }

}
