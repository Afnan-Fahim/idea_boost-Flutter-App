// This file is deprecated and has been removed
//       notifyListeners();
//       return false;
//     }
//   }

//   // Call this after watching a rewarded ad
//   Future<void> addExtraGeneration() async {
//     if (plan == 'free') {
//       dailyLimit++; // Or however you want to handle +1
//       User? user = FirebaseAuth.instance.currentUser;
//       if (user != null) {
//         await _firestoreService.updateUserDocument(user.uid, {
//           'dailyLimit': dailyLimit,
//         });
//       }
//       notifyListeners();
//     }
//   }
// }
