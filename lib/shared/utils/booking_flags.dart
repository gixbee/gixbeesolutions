/// Coerce API / JSON truthy values for booking boolean flags (`isPaid`, etc.).
bool bookingFlagTrue(dynamic v) =>
    v == true || v == 'true' || v == 1 || v == '1';
