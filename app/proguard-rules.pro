# Driver Intelligence — regras R8 para release.
# Room, Hilt, Compose e ML Kit já trazem regras de consumer; aqui só o que é específico do app.

# Mantém nomes de enums persistidos como texto no banco (Classification, DataSource etc.).
-keepclassmembers enum com.driverintelligence.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Stack traces legíveis em relatórios locais de falha.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Anotações referenciadas por bibliotecas mas ausentes em runtime.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
