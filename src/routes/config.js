const { authenticateRequest, jsonResponse, handleCors } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  if (req.method === 'GET') {
    return handleGet(client, user, res, req.env);
  }
  if (req.method === 'PUT') {
    return handlePut(client, user, req, res);
  }

  return jsonResponse(res, 405, { error: 'Method not allowed' });
};

async function handleGet(client, user, res, env) {
  const { data: settings } = await client
    .from('user_settings')
    .select('setting_key, setting_value')
    .eq('user_id', user.id);

  const config = {
    profiles: {},
    active_profile: null,
  };

  for (const s of (settings || [])) {
    if (s.setting_key === 'anthropic_api_key') {
      const val = s.setting_value;
      const profileName = val.profile || 'personal';
      config.profiles[profileName] = {
        label: val.label || profileName,
        key_preview: val.key ? '...' + val.key.slice(-4) : '',
        has_key: !!val.key,
      };
      if (!config.active_profile) config.active_profile = profileName;
    } else if (s.setting_key === 'active_profile') {
      config.active_profile = s.setting_value;
    }
  }

  // If no saved key but a server-wide env key exists, surface that.
  if (Object.keys(config.profiles).length === 0 && env.ANTHROPIC_API_KEY) {
    config.profiles.default = {
      label: 'Default (env)',
      key_preview: '...' + env.ANTHROPIC_API_KEY.slice(-4),
      has_key: true,
    };
    config.active_profile = 'default';
  }

  return jsonResponse(res, 200, config);
}

async function handlePut(client, user, req, res) {
  const { profile, key, label } = req.body || {};
  if (!profile || !key) {
    return jsonResponse(res, 400, { error: 'Missing profile or key' });
  }

  const { error: upsertErr } = await client
    .from('user_settings')
    .upsert({
      user_id: user.id,
      setting_key: 'anthropic_api_key',
      setting_value: { profile, key, label: label || profile },
    }, { onConflict: 'user_id,setting_key' });

  if (upsertErr) {
    return jsonResponse(res, 500, { error: 'Save failed', detail: upsertErr.message });
  }

  return jsonResponse(res, 200, { status: 'saved', active: profile });
}
