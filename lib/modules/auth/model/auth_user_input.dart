class AuthUserInput {
  String email;
  String password;
  String? confirmPassword;

  AuthUserInput({
    required this.email,
    required this.password,
    this.confirmPassword,
  });

  bool isValidEmail() {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool isValidPassword() {
    return password.length >= 6;
  }

  bool doPasswordsMatch() {
    if (confirmPassword == null) return true;
    return password == confirmPassword;
  }
}
