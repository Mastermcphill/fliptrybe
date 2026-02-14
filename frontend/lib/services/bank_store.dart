import 'package:shared_preferences/shared_preferences.dart';

class BankStore {
  static const _kBank = "ft_bank_name";
  static const _kAcctNo = "ft_account_number";
  static const _kAcctName = "ft_account_name";

  Future<Map<String, String>> load() async {
    final sp = await SharedPreferences.getInstance();
    return {
      "bank_name": sp.getString(_kBank) ?? "",
      "account_number": sp.getString(_kAcctNo) ?? "",
      "account_name": sp.getString(_kAcctName) ?? "",
    };
  }

  Future<void> save(
      {required String bankName,
      required String accountNumber,
      required String accountName}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBank, bankName);
    await sp.setString(_kAcctNo, accountNumber);
    await sp.setString(_kAcctName, accountName);
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kBank);
    await sp.remove(_kAcctNo);
    await sp.remove(_kAcctName);
  }
}
