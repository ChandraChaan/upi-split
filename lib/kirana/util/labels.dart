import 'package:intl/intl.dart';
import 'package:kirana_core/kirana_core.dart';

// Dates are shown day-first, the way they are written in India.
String _locale(String language) => language == 'te' ? 'te' : 'en_IN';

String formatDate(DateTime d, String language) =>
    DateFormat('d MMM yyyy', _locale(language)).format(d);

String formatDateTime(DateTime d, String language) =>
    DateFormat('d MMM yyyy, h:mm a', _locale(language)).format(d);

String formatTime(DateTime d, String language) =>
    DateFormat('h:mm a', _locale(language)).format(d);

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Due dates count through the end of the chosen day.
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

String unitLabel(Tr tr, Unit unit) => switch (unit) {
  Unit.piece => tr('unit_piece'),
  Unit.kg => tr('unit_kg'),
  Unit.litre => tr('unit_litre'),
  Unit.packet => tr('unit_packet'),
};

/// Goods sold by weight or volume, where the amount is rarely a whole number.
bool isLooseUnit(Unit unit) => unit == Unit.kg || unit == Unit.litre;

String roleLabel(Tr tr, MemberRole role) => switch (role) {
  MemberRole.owner => tr('role_owner'),
  MemberRole.manager => tr('role_manager'),
  MemberRole.cashier => tr('role_cashier'),
};

String methodLabel(Tr tr, PaymentMethod method) => switch (method) {
  PaymentMethod.cash => tr('cash'),
  PaymentMethod.upi => tr('upi'),
  PaymentMethod.credit => tr('credit'),
};

String khataKindLabel(Tr tr, KhataEntry entry) {
  if (entry.reversesId != null) return tr('khata_reversal');
  return switch (entry.kind) {
    KhataKind.purchase => tr('khata_purchase'),
    KhataKind.payment => tr('khata_payment'),
    KhataKind.adjustment => tr('khata_adjustment'),
  };
}

String stockReasonLabel(Tr tr, StockReason reason) => switch (reason) {
  StockReason.sale => tr('move_sale'),
  StockReason.purchase => tr('move_purchase'),
  StockReason.adjustment => tr('move_adjustment'),
  StockReason.voidSale => tr('move_void'),
};

const List<String> expenseCategories = [
  'rent',
  'electricity',
  'salary',
  'transport',
  'other',
];

/// Known categories are stored by code; custom ones are stored as typed.
String expenseCategoryLabel(Tr tr, String category) => switch (category) {
  'rent' => tr('exp_rent'),
  'electricity' => tr('exp_electricity'),
  'salary' => tr('exp_salary'),
  'transport' => tr('exp_transport'),
  'other' => tr('exp_other'),
  _ => category,
};

/// Turns a repository write label into words for the rejection message.
String operationLabel(Tr tr, String label) => switch (label) {
  'saveCustomer' => tr('op_save_customer'),
  'archiveCustomer' => tr('op_save_customer'),
  'setDueDate' => tr('op_due_date'),
  'recordKhataPurchase' => tr('op_khata_purchase'),
  'recordPayment' => tr('op_payment'),
  'recordAdjustment' => tr('op_adjustment'),
  'reverseKhataEntry' => tr('op_reversal'),
  'logReminder' => tr('op_reminder'),
  'saveProduct' => tr('op_save_product'),
  'setProductActive' => tr('op_save_product'),
  'adjustStock' => tr('op_adjust_stock'),
  'createBill' => tr('op_create_bill'),
  'voidBill' => tr('op_void_bill'),
  'addExpense' => tr('op_add_expense'),
  'voidExpense' => tr('op_void_expense'),
  'saveSupplier' => tr('op_save_supplier'),
  'archiveSupplier' => tr('op_save_supplier'),
  'recordSupplierPurchase' => tr('op_supplier_purchase'),
  'recordSupplierPayment' => tr('op_supplier_payment'),
  'updateStore' => tr('op_update_store'),
  _ => label,
};
