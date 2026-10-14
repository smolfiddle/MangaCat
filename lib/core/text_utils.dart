String normalizeForMatch(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool titlesMatch(String a, String b) =>
    normalizeForMatch(a) == normalizeForMatch(b);
