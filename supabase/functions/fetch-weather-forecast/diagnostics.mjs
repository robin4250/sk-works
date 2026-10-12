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
