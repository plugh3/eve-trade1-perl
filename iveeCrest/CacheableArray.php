<?php
/**
 * CacheableArray class file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/CacheableArray.php
 */

namespace iveeCrest;

/**
 * CacheableArray provides a minimal implementation of the ICacheable interface to allow arrays to be cached.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/CacheableArray.php
 */
class CacheableArray extends \stdClass implements ICacheable
{
    /**
     * @var string $key under which the object will be stored in cache
     */
    protected $key;

    /**
     * @var int $ttl the cache time to live in seconds
     */
    protected $ttl;

    /**
     * @var array $data payload
     */
    public $data = array();

    /**
     * Construct a CacheableArray object.
     *
     * @param string $key under which the object will be stored in cache
     * @param int $ttl the cache time to live in seconds
     *
     * @return \iveeCrest\CacheableArray
     */
    public function __construct($key, $ttl)
    {
        $this->key = $key;
        $this->ttl = (int) $ttl;    
    }

    /**
     * Returns the cache time to live in seconds
     *
     * @return int
     */
    public function getCacheTTL()
    {
        return $this->ttl;
    }

    /**
     * Returns the key under which the object is cached
     *
     * @return string
     */
    public function getKey()
    {
        return $this->key;
    }
}
