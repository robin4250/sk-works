// Only fixed enums may enter operational logs. Never serialize caught errors.
export const weatherFailureCodes = new Set([
  'server_configuration', 'authentication', 'request', 'adapters',
  'region_lookup', 'region_missing', 'geocoding', 'geocoding_provider_missing',
  'geocoding_key_missing', 'calendar', 'provider_setting', 'provider_unavailable',
  'forecast_fetch', 'openweather_key_missing', 'weatherkit_configuration_missing',
  'response_validation', 'timeout',
]);
export class WeatherConfigurationError extends Error {
  constructor(code) { super('Weather configuration unavailable'); this.code = code; }
}
export function logWeatherFailure(stage, error, logger = console.warn) {
  const code = error instanceof WeatherConfigurationError && weatherFailureCodes.has(error.code)
    ? error.code : ['AbortError', 'TimeoutError'].includes(error?.name) ? 'timeout'
    : weatherFailureCodes.has(stage) ? stage : 'server_configuration';
  logger(`weather_failure:${code}`);
}
// Report only missing names, never values. Called after verified-user region read.
export function logWeatherConfigurationGaps(env, logger = console.warn) {
  const names = [
    ['WEATHER_GEOCODING_API_KEY', 'geocoding_key'],
    ['OPENWEATHER_API_KEY', 'openweather_key'],
    ['WEATHERKIT_TEAM_ID', 'weatherkit_team'],
    ['WEATHERKIT_SERVICE_ID', 'weatherkit_service'],
    ['WEATHERKIT_KEY_ID', 'weatherkit_key_id'],
    ['WEATHERKIT_PRIVATE_KEY', 'weatherkit_private_key'],
  ];
  for (const [name, code] of names) {
    const present = typeof env(name) === 'string' && env(name).trim().length > 0;
    if (!present) logger(`weather_configuration_missing:${code}`);
  }
}
