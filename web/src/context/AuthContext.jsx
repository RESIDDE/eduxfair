import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';

const AuthContext = createContext(null);

/**
 * Session, profile and institution membership.
 *
 * Which console a user sees is decided by `profiles.role` — but that is a
 * convenience, not the security boundary. Row-level security enforces access
 * regardless of what the client renders, so a student who somehow reached
 * /admin would simply see empty tables.
 */
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [memberships, setMemberships] = useState([]);
  const [loading, setLoading] = useState(true);

  const loadProfile = useCallback(async (userId) => {
    if (!userId) {
      setProfile(null);
      setMemberships([]);
      return;
    }

    const [{ data: profileRow }, { data: memberRows }] = await Promise.all([
      supabase.from('profiles').select('*').eq('id', userId).maybeSingle(),
      supabase
        .from('institution_members')
        .select('institution_id, member_role, institutions(*)')
        .eq('profile_id', userId),
    ]);

    setProfile(profileRow ?? null);
    setMemberships(memberRows ?? []);
  }, []);

  useEffect(() => {
    let active = true;

    supabase.auth.getSession().then(async ({ data }) => {
      if (!active) return;
      setSession(data.session);
      await loadProfile(data.session?.user?.id);
      if (active) setLoading(false);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange(
      async (_event, nextSession) => {
        if (!active) return;
        setSession(nextSession);
        await loadProfile(nextSession?.user?.id);
      },
    );

    return () => {
      active = false;
      subscription.subscription.unsubscribe();
    };
  }, [loadProfile]);

  const signIn = useCallback(async (email, password) => {
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    return error;
  }, []);

  const signUp = useCallback(
    async (email, password, fullName) => {
      const { data, error } = await supabase.functions.invoke('send-auth-email', {
        body: {
          action: 'signup',
          email: email.trim(),
          password,
          fullName: fullName.trim(),
          role: 'institution_member',
        },
      });
      if (error) return error;
      if (data?.ok !== true) {
        return new Error(data?.error ?? 'Could not create account');
      }
      return signIn(email, password);
    },
    [signIn],
  );

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setProfile(null);
    setMemberships([]);
  }, []);

  const value = useMemo(() => {
    // One institution is the common case; the first membership is the active
    // one until there is a reason to build a switcher.
    const membership = memberships[0] ?? null;

    return {
      session,
      user: session?.user ?? null,
      profile,
      loading,
      role: profile?.role ?? null,
      isAdmin: profile?.role === 'admin',
      isInstitution: profile?.role === 'institution_member',
      memberships,
      institution: membership?.institutions ?? null,
      institutionId: membership?.institution_id ?? null,
      isOwner: membership?.member_role === 'owner',
      refresh: () => loadProfile(session?.user?.id),
      signIn,
      signUp,
      signOut,
    };
  }, [session, profile, memberships, loading, loadProfile, signIn, signUp, signOut]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside AuthProvider');
  return context;
}
