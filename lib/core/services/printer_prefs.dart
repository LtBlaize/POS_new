/// Shared SharedPreferences keys for the selected thermal printer.
/// Used by both PrinterSettingsSection (persists the choice) and
/// ThermalPrintService (resolves which printer to print to). Keeping
/// these in one place is what closes the gap between "selected printer"
/// and "printer actually printed to."
class PrinterPrefsKeys {
  static const is58mm = 'printer_is_58mm';
  static const name = 'printer_selected_name';
  static const url = 'printer_selected_url';
}