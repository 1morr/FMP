import 'package:analyzer/dart/ast/ast.dart';

/// [expression] 是不是名為 [name] 的識別字，含帶 import 前綴的寫法
/// （`ScaffoldMessenger`、`m.ScaffoldMessenger`）。
bool isNamedReference(Expression? expression, String name) =>
    switch (expression) {
      SimpleIdentifier(name: final actual) => actual == name,
      PrefixedIdentifier(identifier: SimpleIdentifier(name: final actual)) =>
        actual == name,
      _ => false,
    };
