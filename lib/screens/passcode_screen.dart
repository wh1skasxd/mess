import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PasscodeScreen extends StatefulWidget {
  final bool isSetup; // true - придумываем пароль, false - вводим для входа
  final VoidCallback onSuccess;

  const PasscodeScreen({super.key, required this.isSetup, required this.onSuccess});

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  String _enteredCode = '';
  String? _firstCode; 
  String _errorText = '';

  void _onKeyPress(String key) async {
    if (_enteredCode.length < 4) {
      setState(() {
        _enteredCode += key;
        _errorText = '';
      });
    }

    if (_enteredCode.length == 4) {
      await Future.delayed(const Duration(milliseconds: 200)); 
      
      if (widget.isSetup) {
        // СОЗДАНИЕ ПАРОЛЯ
        if (_firstCode == null) {
          setState(() {
            _firstCode = _enteredCode;
            _enteredCode = '';
          });
        } else {
          if (_firstCode == _enteredCode) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('app_passcode', _enteredCode);
            widget.onSuccess();
          } else {
            setState(() {
              _errorText = 'Пароли не совпадают. Попробуйте еще раз.';
              _firstCode = null;
              _enteredCode = '';
            });
          }
        }
      } else {
        // РАЗБЛОКИРОВКА
        final prefs = await SharedPreferences.getInstance();
        final savedCode = prefs.getString('app_passcode');
        if (savedCode == _enteredCode) {
          widget.onSuccess(); 
        } else {
          setState(() {
            _errorText = 'Неверный ПИН-код';
            _enteredCode = '';
          });
        }
      }
    }
  }

  void _onDelete() {
    if (_enteredCode.isNotEmpty) {
      setState(() {
        _enteredCode = _enteredCode.substring(0, _enteredCode.length - 1);
        _errorText = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.isSetup 
        ? (_firstCode == null ? 'Придумайте ПИН-код' : 'Повторите ПИН-код')
        : 'Введите ПИН-код';

    return PopScope(
      canPop: widget.isSetup, // Блокируем кнопку "Назад" при разблокировке
      child: Scaffold(
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline, size: 60, color: Colors.blue),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(_errorText, style: const TextStyle(color: Colors.red, fontSize: 16)),
              const SizedBox(height: 30),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isFilled = index < _enteredCode.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? Colors.blue : Colors.transparent,
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                  );
                }),
              ),
              
              const Spacer(),
              _buildNumPad(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumPad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 1.5,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 1; i <= 9; i++) _buildKey(i.toString()),
          const SizedBox.shrink(),
          _buildKey('0'),
          GestureDetector(
            onTap: _onDelete,
            child: const Center(child: Icon(Icons.backspace_outlined, size: 30)),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String text) {
    return GestureDetector(
      onTap: () => _onKeyPress(text),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.withOpacity(0.1),
        ),
        child: Center(
          child: Text(text, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}