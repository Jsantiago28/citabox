import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabasePublishableKey) {
  // No lanzamos error duro en build/dev para no romper placeholders,
  // pero avisamos claramente en consola.
  console.warn(
    '[supabaseClient] Faltan VITE_SUPABASE_URL o VITE_SUPABASE_PUBLISHABLE_KEY. ' +
      'Copia .env.example a .env.local y completa los valores.'
  );
}

// Instancia única y centralizada del cliente de Supabase.
// Todo el resto de la app debe importar este archivo en lugar de
// crear nuevas instancias de createClient.
export const supabase = createClient(supabaseUrl ?? '', supabasePublishableKey ?? '');
