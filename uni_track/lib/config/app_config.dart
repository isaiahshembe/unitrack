class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mjlxofeciyxbagygyxrc.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qbHhvZmVjaXl4YmFneWd5eHJjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3OTE0MzAsImV4cCI6MjA5MjM2NzQzMH0.08h8LNzoTFVE2EpfSo-7M8MytoMtM83vvnXTGCDF_1E',
  );

  static const webApiUrl = String.fromEnvironment(
    'WEB_API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const useWebAiForComplaints = bool.fromEnvironment(
    'USE_WEB_AI_FOR_COMPLAINTS',
    defaultValue: true,
  );
}
