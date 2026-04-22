// FileRedirectionDylib.mm
// Compilar com: clang -shared -o FileRedirectionDylib.dylib FileRedirectionDylib.mm -framework Foundation -framework CydiaSubstrate

#import <Foundation/Foundation.h>
#import <string>
#import <vector>
#import <dlfcn.h>

// Para MSHookFunction (Cydia Substrate)
// Se CydiaSubstrate não estiver disponível, pode-se usar fishhook ou outras técnicas de hooking
// Para simplificar, assumimos que CydiaSubstrate será linkado.
#if __has_include(<substrate.h>)
#import <substrate.h>
#else
// Fallback para compilação sem Substrate, mas o hooking não funcionará sem uma alternativa.
// Isso é apenas para que o código compile, não para funcionar.
#define MSHookFunction(original, hook, old) do { \
    NSLog(@"MSHookFunction not available. Hooking will not occur."); \
} while(0)
#endif

// --- Configurações --- //
// Nome do arquivo original que será interceptado
const char* ORIGINAL_FILENAME = "resources.assets";
// Nome do arquivo modificado (shadow file) que será entregue no lugar do original
const char* SHADOW_FILENAME = "UnityCache.dat";

// --- Funções Originais --- //
// Ponteiros para as funções originais que serão hookadas
static FILE* (*original_fopen)(const char* filename, const char* mode);
static int (*original_open)(const char* path, int oflag, ...);

// --- Funções Hookadas --- //

// Hook para fopen
FILE* hooked_fopen(const char* filename, const char* mode) {
    std::string filename_str = filename;
    
    // Verifica se o arquivo solicitado é o ORIGINAL_FILENAME
    if (filename_str.find(ORIGINAL_FILENAME) != std::string::npos) {
        // Constrói o caminho para o SHADOW_FILENAME
        // Assumimos que o SHADOW_FILENAME está na mesma pasta do ORIGINAL_FILENAME
        size_t last_slash_pos = filename_str.rfind('/');
        std::string shadow_path = filename_str.substr(0, last_slash_pos + 1) + SHADOW_FILENAME;
        
        NSLog(@"[FileRedirectionDylib] Interceptado fopen: %s -> Redirecionando para: %s", filename, shadow_path.c_str());
        return original_fopen(shadow_path.c_str(), mode);
    }
    
    // Se não for o arquivo alvo, chama a função original
    return original_fopen(filename, mode);
}

// Hook para open (para sistemas de arquivos de baixo nível)
int hooked_open(const char* path, int oflag, ...) {
    std::string path_str = path;
    
    // Verifica se o arquivo solicitado é o ORIGINAL_FILENAME
    if (path_str.find(ORIGINAL_FILENAME) != std::string::npos) {
        // Constrói o caminho para o SHADOW_FILENAME
        size_t last_slash_pos = path_str.rfind('/');
        std::string shadow_path = path_str.substr(0, last_slash_pos + 1) + SHADOW_FILENAME;
        
        NSLog(@"[FileRedirectionDylib] Interceptado open: %s -> Redirecionando para: %s", path, shadow_path.c_str());
        
        // open pode ter um terceiro argumento (mode) se O_CREAT for usado
        // Precisamos passar os argumentos variáveis corretamente
        va_list args;
        va_start(args, oflag);
        int mode = va_arg(args, int);
        va_end(args);
        
        return original_open(shadow_path.c_str(), oflag, mode);
    }
    
    // Se não for o arquivo alvo, chama a função original
    va_list args;
    va_start(args, oflag);
    int mode = va_arg(args, int);
    va_end(args);
    return original_open(path, oflag, mode);
}

// --- Construtor da Dylib --- //
// Esta função é executada quando a Dylib é carregada no processo do jogo
__attribute__((constructor))
static void initialize() {
    NSLog(@"[FileRedirectionDylib] Dylib carregada. Iniciando hooking...");
    
    // Hook fopen
    MSHookFunction((void*)fopen, (void*)hooked_fopen, (void**)&original_fopen);
    
    // Hook open
    // open é mais complexo devido aos argumentos variáveis. Precisamos garantir que
    // o dlsym encontre a versão correta (com ou sem mode_t).
    // Para robustez, é melhor hookar a versão com 3 argumentos se O_CREAT for possível.
    // No entanto, MSHookFunction requer o endereço exato. Vamos usar dlsym.
    original_open = (int (*)(const char*, int, ...))dlsym(RTLD_DEFAULT, "open");
    if (original_open) {
        MSHookFunction((void*)original_open, (void*)hooked_open, (void**)&original_open);
    } else {
        NSLog(@"[FileRedirectionDylib] Erro: Não foi possível encontrar a função open.");
    }
    
    NSLog(@"[FileRedirectionDylib] Hooking concluído.");
}

// --- Exemplo de uso de Objective-C para logging (opcional) ---
// @interface MyLogger : NSObject
// + (void)logMessage:(NSString*)message;
// @end
//
// @implementation MyLogger
// + (void)logMessage:(NSString*)message {
//     NSLog(@"[MyLogger] %@", message);
// }
// @end
