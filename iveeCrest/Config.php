<?php
/**
 * Main configuration file for iveeCrest.
 *
 * Copy and edit this file according to your environment. The edited file should be saved as Config.php
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/Config_template.php
 */

namespace iveeCrest;

/**
 * The Config class holds the basic iveeCrest configuration for cache and classnames.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/Config_template.php
 */
class Config
{
    /////////////////////
    // Edit below here //
    /////////////////////

    //Cache config
    protected static $cacheHost   = 'localhost';
    protected static $cachePort   = '11211'; //memcached default: 11211, redis default: 6379
    protected static $cachePrefix = 'iveeCrest_';

    //CREST config
    //protected static $crestBaseUrl       = 'https://crest-tq.eveonline.com/';
    protected static $crestBaseUrl       = 'https://public-crest.eveonline.com/'; // no-auth CREST
    protected static $clientId           = 'e5a122800a134da2ad4b0e01664b627b';
    protected static $clientSecret       = 'YQ5iCxkAL3KjBCk9djCDKKJlsm9IJmZlqRQHycSb';
    protected static $clientRefreshToken = '2-X4wdpBzGMTkpy8bdk0jg-gi6YfwVWyp_G9PbJtAME1';

    //change the application name in the parenthesis to your application. It is used when accessing the CREST API.
    protected static $userAgent = 'iveeCrest/0.1 (draconic1)';

    //To enable developers to extend iveeCrest with their own classes (inheriting from iveeCrest), it dynamically looks
    //up class names before instantiating them. This array maps from class "nicknames" to fully qualified names, which
    //can then be used by the autoloader. Change according to your needs.
    protected static $classes = array(
        'Cache'                 => '\iveeCrest\DraconicCacheWrapper', //change to '\iveeCrest\RedisWrapper' if using Redis
        'CacheableArray'        => '\iveeCrest\CacheableArray',
        'Client'                => '\iveeCrest\Client',
        'CurlWrapper'           => '\iveeCrest\CurlWrapper',
        'EndpointHandler'       => '\iveeCrest\EndpointHandler',
        'Response'              => '\iveeCrest\Response',
        'CrestException'              => '\iveeCrest\Exceptions\CrestException',
        'InvalidArgumentException'    => '\iveeCrest\Exceptions\InvalidArgumentException',
        'IveeCrestException'          => '\iveeCrest\Exceptions\IveeCrestException',
        'KeyNotFoundInCacheException' => '\iveeCrest\Exceptions\KeyNotFoundInCacheException',
    );

    ////////////////////////////
    // Do not edit below here //
    ////////////////////////////

    /**
     * Instantiates Config object. Private so this class is only used as static.
     *
     * @return Config
     */
    private function __construct()
    {
    }

    /**
     * Returns if cache use is configured or not
     *
     * @return bool
     */
    public static function getUseCache()
    {
        return static::$useCache;
    }

    /**
     * Returns configured cache host name
     *
     * @return string
     */
    public static function getCacheHost()
    {
        return static::$cacheHost;
    }

    /**
     * Returns configured cache port
     *
     * @return int
     */
    public static function getCachePort()
    {
        return static::$cachePort;
    }

    /**
     * Returns configured cache prefix for keys stored by iveeCrest
     *
     * @return string
     */
    public static function getCachePrefix()
    {
        return static::$cachePrefix;
    }

    /**
     * Returns configured CREST base URL
     *
     * @return string
     */
    public static function getCrestBaseUrl()
    {
        return static::$crestBaseUrl;
    }

    /**
     * Returns configured CREST client ID
     *
     * @return string
     */
    public static function getClientId()
    {
        return static::$clientId;
    }

    /**
     * Returns configured CREST client secret
     *
     * @return string
     */
    public static function getClientSecret()
    {
        return static::$clientSecret;
    }

    /**
     * Returns configured CREST user specific refresh token
     *
     * @return string
     */
    public static function getClientRefreshToken()
    {
        return static::$clientRefreshToken;
    }

    /**
     * Returns configured user agent to be used by the CREST client
     *
     * @return string
     */
    public static function getUserAgent()
    {
        return static::$userAgent;
    }

    /**
     * Returns the fully qualified name of classes to instantiate for a given class nickname. This is used extensively
     * in iveeCrest to allow for configurable class instantiation
     *
     * @param string $classNickname a short name for the class
     *
     * @return string
     */
    public static function getIveeClassName($classNickname)
    {
        if (isset(static::$classes[$classNickname]))
            return static::$classes[$classNickname];
        else
            exit('Fatal Error: No class configured  for "' . $classNickname . '" in iveeCrest' . DIRECTORY_SEPARATOR
                . 'Config.php' . PHP_EOL);
    }
}
