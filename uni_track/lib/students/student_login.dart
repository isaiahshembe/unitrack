import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uni_track/landindPage/landing_page.dart';
import 'package:uni_track/students/students_mainpage.dart';
import 'package:uni_track/students/students_register.dart';

class StudentLogin extends StatefulWidget {
  const StudentLogin({super.key});

  @override
  State<StudentLogin> createState() => _StudentLoginState();
}

class _StudentLoginState extends State<StudentLogin> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Validate form
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // Step 1: Sign in with Supabase Auth
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        throw Exception('Invalid email or password');
      }

      final userId = authResponse.user!.id;
      print('🔍 User ID: $userId');

      // Step 2: Get student data
      Map<String, dynamic>? studentData = await _fetchStudentData(userId);

      if (studentData == null) {
        await _supabase.auth.signOut();
        throw Exception('Student profile not found. Please register first.');
      }

      // Step 3: Ensure all required fields exist
      studentData = _ensureRequiredFields(studentData);

      // Success - navigate to main page
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Login successful!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (c) => StudentsMainpage(userData: studentData!),
          ),
        );
      }
    } on AuthException catch (e) {
      _handleAuthError(e);
    } on PostgrestException catch (e) {
      _handleDatabaseError(e);
    } catch (e) {
      _handleGenericError(e);
    }
  }

  // Method to ensure all required fields exist in student data
  Map<String, dynamic> _ensureRequiredFields(Map<String, dynamic> data) {
    final Map<String, dynamic> result = Map.from(data);

    // Ensure all required fields have default values if null
    result['id'] = result['id'] ?? '';
    result['full_name'] = result['full_name'] ?? 'Student';
    result['student_id'] = result['student_id'] ?? 'N/A';
    result['email'] = result['email'] ?? '';
    result['phone'] = result['phone'] ?? 'N/A';
    result['college_id'] = result['college_id'];
    result['course_id'] = result['course_id'];

    // College name
    result['college_name'] =
        result['college_name'] ?? result['colleges']?['name'] ?? 'Not Assigned';

    // Course name and code
    if (result['courses'] != null) {
      final course = result['courses'] as Map<String, dynamic>;
      result['course_name'] = course['name'] ?? 'Not Assigned';
      result['course_code'] = course['course_code'] ?? 'N/A';
      result['department_id'] = course['department_id'];
    } else {
      result['course_name'] = result['course_name'] ?? 'Not Assigned';
      result['course_code'] = result['course_code'] ?? 'N/A';
      result['department_id'] = result['department_id'];
    }

    // Department name
    result['department_name'] = result['department_name'] ?? 'Not Assigned';

    print('📊 Final student data: $result');
    return result;
  }

  // Method to fetch student data using the view
  Future<Map<String, dynamic>?> _fetchStudentData(String userId) async {
    try {
      print('📊 Fetching from student_details view...');
      final response = await _supabase
          .from('student_details')
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      print('📊 View result: $response');

      if (response != null) {
        return Map<String, dynamic>.from(response);
      }
      return null;
    } catch (e) {
      print('⚠️ View query failed: $e');
      return null;
    }
  }

  // Fallback: Direct query with relationships
  Future<Map<String, dynamic>?> _fetchStudentDataDirect(String userId) async {
    try {
      print('📊 Fetching from students table directly...');

      // Get student record
      final studentResponse = await _supabase
          .from('students')
          .select(
              '*, colleges(name), courses(name, course_code, department_id)')
          .eq('id', userId)
          .maybeSingle();

      if (studentResponse == null) {
        print('❌ No student record found');
        return null;
      }

      print('✅ Student found: $studentResponse');
      final studentData = Map<String, dynamic>.from(studentResponse);

      // Extract college name
      if (studentData['colleges'] != null) {
        studentData['college_name'] = studentData['colleges']['name'];
      }

      // Extract course and department details
      if (studentData['courses'] != null) {
        final course = studentData['courses'] as Map<String, dynamic>;
        studentData['course_name'] = course['name'];
        studentData['course_code'] = course['course_code'];
        studentData['department_id'] = course['department_id'];
      }

      return studentData;
    } catch (e) {
      print('❌ Direct query failed: $e');
      return null;
    }
  }

  // Error handling methods
  void _handleAuthError(AuthException e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      String errorMessage;
      switch (e.message) {
        case 'Invalid login credentials':
          errorMessage = '❌ Invalid email or password. Please try again.';
          break;
        case 'Email not confirmed':
          errorMessage = '📧 Please verify your email address first.';
          break;
        case 'User not found':
          errorMessage = '❌ No account found with this email.';
          break;
        default:
          errorMessage = '🔐 Authentication error: ${e.message}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleDatabaseError(PostgrestException e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      print('❌ Database error: ${e.message}');
      print('❌ Error code: ${e.code}');

      String errorMessage = '⚠️ Error fetching student data. Please try again.';

      if (e.message.contains('relation') ||
          e.message.contains('does not exist')) {
        errorMessage =
            '⚠️ Database configuration error. Please contact support.';
      } else if (e.message.contains('permission denied')) {
        errorMessage = '🔒 Permission denied. Please contact support.';
      } else if (e.message.contains('Could not find')) {
        errorMessage = '❌ Student profile not found. Please register first.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleGenericError(dynamic e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      print('❌ Unexpected error: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Reset Password',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your email to receive a password reset link.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'student@students.mak.ac.ug',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.email),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Send Reset Link',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      final email = emailController.text.trim();
      if (email.isNotEmpty) {
        try {
          await _supabase.auth.resetPasswordForEmail(email);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Password reset link sent! Check your email.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Error: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }
    emailController.dispose();
  }

  // Validators
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!value.endsWith('@students.mak.ac.ug')) {
      return 'Please use your Makerere University email (@students.mak.ac.ug)';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
              // Logo
              Image.asset(
                'images/muklogo.png',
                height: 300,
                width: 300,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.school,
                    size: 150,
                    color: Colors.green,
                  );
                },
              ),

              // Title
              Text(
                'Student Login',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome back! Please login to continue',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 40),

              // Login Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email Field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Makerere Email',
                        labelStyle: TextStyle(color: Colors.grey[700]),
                        hintText: 'student@students.mak.ac.ug',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: Icon(Icons.email, color: Colors.green[600]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: Colors.green,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: Colors.grey[700]),
                        prefixIcon: Icon(Icons.lock, color: Colors.green[600]),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: Colors.green,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 10),

                    // Forgot Password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _handleForgotPassword,
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Login Button
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
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'LOGIN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Divider
                    Row(
                      children: [
                        Expanded(
                          child: Divider(color: Colors.grey[300], thickness: 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: Colors.grey[300], thickness: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Register Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StudentsRegister(),
                            ),
                          ),
                          child: Text(
                            'Register Now',
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Go to landing page",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LandingPage(),
                            ),
                          ),
                          child: Text(
                            'Landing Page',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
