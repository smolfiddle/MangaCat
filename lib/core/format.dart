import 'package:intl/intl.dart';

String formatDateTime(DateTime value) => DateFormat('d MMM yyyy, HH:mm').format(value);

String formatDay(DateTime value) => DateFormat('d MMM yyyy').format(value);
