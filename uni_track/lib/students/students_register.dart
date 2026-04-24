import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/students/student_login.dart';

class StudentsRegister extends StatefulWidget {
  const StudentsRegister({super.key});

  @override
  State<StudentsRegister> createState() => _StudentsRegisterState();
}

class _StudentsRegisterState extends State<StudentsRegister> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  final _supabase = Supabase.instance.client;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _agreeTerms = false;

  // College and Course
  List<Map<String, dynamic>> _colleges = [];
  List<Map<String, dynamic>> _courses = [];
  String? _selectedCollegeId;
  String? _selectedCourseId;

  @override
  void initState() {
    super.initState();
    _fetchColleges();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _studentIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchColleges() async {
    try {
      final response = await _supabase
          .from('colleges')
          .select()
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _colleges = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching colleges: $e');
    }
  }

  Future<void> _fetchCoursesByCollege(String collegeId) async {
    if (mounted) {
      setState(() {
        _courses = [];
        _selectedCourseId = null;
      });
    }

    try {
      final departments = await _supabase
          .from('departments')
          .select('id')
          .eq('college_id', int.parse(collegeId))
          .timeout(const Duration(seconds: 10));

      if (departments.isEmpty) {
        if (mounted) {
          setState(() {
            _courses = [];
          });
        }
        return;
      }

      final List<int> departmentIds = [];
      for (var dept in departments) {
        departmentIds.add(dept['id'] as int);
      }

      final response = await _supabase
          .from('courses')
          .select('*, departments(name)')
          .inFilter('department_id', departmentIds)
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _courses = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching courses: $e');
      if (mounted) {
        setState(() {
          _courses = [];
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreeTerms) {
      _showSnackBar('Please agree to the terms and conditions', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final studentId = _studentIdController.text.trim();
      final fullName = _fullNameController.text.trim();
      final phone = _phoneController.text.trim();

      // Step 1: Create auth user in Supabase Auth
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'student_id': studentId,
          'phone': phone,
          'role': 'student',
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create user account');
      }

      final userId = authResponse.user!.id;

      // Step 2: Save student details to students table
      // Use insert with explicit error handling
      try {
        await _supabase.from('students').insert({
          'id': userId,
          'full_name': fullName,
          'student_id': studentId,
          'email': email,
          'phone': phone.isNotEmpty ? phone : null,
          'college_id': int.parse(_selectedCollegeId!),
          'course_id': int.parse(_selectedCourseId!),
          'created_at': DateTime.now().toIso8601String(),
        });

        debugPrint('Student saved to database successfully');
      } catch (dbError) {
        debugPrint('Database error: $dbError');
        // If database insert fails, we should still proceed since auth succeeded
        // But log the error for debugging
        if (dbError is PostgrestException) {
          debugPrint('PostgREST error code: ${dbError.code}');
          debugPrint('PostgREST error message: ${dbError.message}');
          debugPrint('PostgREST error details: ${dbError.details}');
        }
        rethrow; // Re-throw to show error to user
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registration successful! Please check your email to verify your account.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (c) => const StudentLogin()),
        );
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        String errorMessage = 'Registration failed';
        if (e is PostgrestException) {
          debugPrint('PostgREST error: ${e.message}');
          if (e.code == '23505') {
            if (e.message.contains('student_id')) {
              errorMessage = 'A student with this Student ID already exists';
            } else if (e.message.contains('email')) {
              errorMessage =
                  'A student with this email already exists. Please login instead.';
            } else {
              errorMessage = 'Duplicate entry. Please check your details.';
            }
          } else if (e.code == '23503') {
            errorMessage = 'Invalid college or course selection';
          } else if (e.code == '42501') {
            errorMessage = 'Permission denied. Please check database policies.';
          } else {
            errorMessage = 'Database error: ${e.message}';
          }
        } else if (e is AuthException) {
          errorMessage = e.message;
        } else {
          errorMessage = e.toString();
        }

        _showSnackBar(errorMessage, Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Validation methods remain the same...
  String? _validateFullName(String? value) {
    if (value == null || value.trim().isEmpty)
      return 'Please enter your full name';
    if (value.trim().length < 3) return 'Name must be at least 3 characters';
    return null;
  }

  String? _validateStudentId(String? value) {
    if (value == null || value.trim().isEmpty)
      return 'Please enter your student ID';
    if (!RegExp(r'^\d{10}$').hasMatch(value.trim()))
      return 'Please enter a valid 10-digit student ID';
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter your email';
    if (!value.trim().endsWith('@students.mak.ac.ug'))
      return 'Please use your Makerere University email (@students.mak.ac.ug)';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value != null && value.isNotEmpty) {
      if (!RegExp(r'^\d{10}$').hasMatch(value.trim()))
        return 'Please enter a valid 10-digit phone number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Student Registration',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_add,
                  size: 50,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please fill in the details to register',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 30),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Full Name
                    _buildTextField(
                      controller: _fullNameController,
                      label: 'Full Name',
                      icon: Icons.person,
                      validator: _validateFullName,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),

                    // Student ID
                    _buildTextField(
                      controller: _studentIdController,
                      label: 'Student ID',
                      icon: Icons.badge,
                      hintText: 'e.g., 2024123456',
                      keyboardType: TextInputType.number,
                      validator: _validateStudentId,
                    ),
                    const SizedBox(height: 16),

                    // Email
                    _buildTextField(
                      controller: _emailController,
                      label: 'Makerere Email',
                      icon: Icons.email,
                      hintText: 'student@students.mak.ac.ug',
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),

                    // College Dropdown - FIXED OVERFLOW
                    _buildDropdown(
                      value: _selectedCollegeId,
                      label: 'College',
                      icon: Icons.business,
                      hint: 'Select your college',
                      items: _colleges.map((college) {
                        return DropdownMenuItem<String>(
                          value: college['id'].toString(),
                          child: Text(
                            college['name'],
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCollegeId = value;
                          _selectedCourseId = null;
                          if (value != null) {
                            _fetchCoursesByCollege(value);
                          }
                        });
                      },
                      validator: (value) => value == null || value.isEmpty
                          ? 'Please select your college'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Course Dropdown - FIXED OVERFLOW
                    if (_selectedCollegeId != null)
                      _buildDropdown(
                        value: _selectedCourseId,
                        label: 'Course',
                        icon: Icons.menu_book,
                        hint: _courses.isEmpty
                            ? 'No courses available'
                            : 'Select your course',
                        items: _courses.map((course) {
                          return DropdownMenuItem<String>(
                            value: course['id'].toString(),
                            child: Text(
                              course['name'],
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          );
                        }).toList(),
                        onChanged: _courses.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedCourseId = value;
                                });
                              },
                        validator: (value) => value == null || value.isEmpty
                            ? 'Please select your course'
                            : null,
                      ),
                    if (_selectedCollegeId != null) const SizedBox(height: 16),

                    // Phone Number
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number (Optional)',
                      icon: Icons.phone,
                      hintText: 'e.g., 0778123456',
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 16),

                    // Password
                    _buildTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.green[600],
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password
                    _buildTextField(
                      controller: _confirmPasswordController,
                      label: 'Confirm Password',
                      icon: Icons.lock_outline,
                      obscureText: _obscureConfirmPassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.green[600],
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        ),
                      ),
                      validator: _validateConfirmPassword,
                    ),
                    const SizedBox(height: 16),

                    // Terms and Conditions
                    Row(
                      children: [
                        Checkbox(
                          value: _agreeTerms,
                          onChanged: (value) =>
                              setState(() => _agreeTerms = value ?? false),
                          activeColor: Colors.green,
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _agreeTerms = !_agreeTerms),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                                children: [
                                  const TextSpan(text: 'I agree to the '),
                                  TextSpan(
                                    text: 'Terms and Conditions',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Register Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleRegister,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'REGISTER',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Login Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Already have an account? ",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Login Here',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reusable text field builder
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        hintText: hintText,
        prefixIcon: Icon(icon, color: Colors.green[600]),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: validator,
    );
  }

  // Reusable dropdown builder - FIXED FOR OVERFLOW
  Widget _buildDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    void Function(String?)? onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        prefixIcon: Icon(icon, color: Colors.green[600]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        isDense: true,
      ),
      value: value,
      hint: Text(hint, style: const TextStyle(fontSize: 14)),
      isExpanded: true,
      menuMaxHeight: 300,
      items: items,
      onChanged: onChanged,
      validator: validator,
      selectedItemBuilder: (BuildContext context) {
        return items.map<Widget>((item) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              item.child is Text ? (item.child as Text).data ?? '' : '',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 14),
            ),
          );
        }).toList();
      },
    );
  }
}
