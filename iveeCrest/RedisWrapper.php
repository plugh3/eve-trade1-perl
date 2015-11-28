<?php
/**
 * RedisWrapper class file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/RedisWrapper.php
 */

namespace iveeCrest;

/**
 * RedisWrapper provides caching functionality for iveeCrest based on Redis and phpredis (php5-redis)
 *
 * Pulling data from CREST is a relative expensive process thats slows down the client application and puts load onto
 * CCP's infrastructure. CCP thus asks developers to implement client side caching mechanisms, respecting the cache
 * times specified in the response header as much as possible.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/RedisWrapper.php
 */
class RedisWrapper implements ICache
{
    /**
     * @var \Redis $redis holds the Redis object
     */
    protected $redis;

    /**
     * @var int $hits stores the number of cache hits.
     */
    protected $hits = 0;

    /**
     * @var string $uniqId to be used to separate objects in addition to their key identifiers, for instance in a
     * multi-user scenario.
     */
    protected $uniqId;

    /**
     * Constructor.
     *
     * @param string $uniqId to be used to separate objects in addition to their key identifiers, for instance in a
     * multi-user scenario.
     *
     * @return \iveeCrest\RedisWrapper
     */
    public function __construct($uniqId)
    {
        $this->redis = new \Redis;
        $this->redis->connect(Config::getCacheHost(), Config::getCachePort());
        $this->redis->setOption(\Redis::OPT_PREFIX, Config::getCachePrefix());
        $this->uniqId = $uniqId;
    }

    /**
     * Stores item in Redis.
     *
     * @param \iveeCrest\ICacheable $item to be stored
     *
     * @return boolean true on success
     */
    public function setItem(ICacheable $item)
    {
        $key = md5($this->uniqId . '_' . $item->getKey());
        $ttl = $item->getCacheTTL();

        //emulate memcached behaviour: TTLs over 30 days are interpreted as (absolute) UNIX timestamps
        if ($ttl > 2592000) {
            $this->redis->set(
                $key,
                serialize($item)
            );
            return $this->redis->expireAt($key, $ttl);
        } else {
            return $this->redis->setex(
                $key,
                $ttl,
                serialize($item)
            );
        }
    }

    /**
     * Gets item from Redis.
     *
     * @param string $key under which the item is stored
     *
     * @return \iveeCrest\ICacheable
     * @throws \iveeCrest\Exceptions\KeyNotFoundInCacheException if key is not found
     */
    public function getItem($key)
    {
        $item = $this->redis->get(md5($this->uniqId . '_' . $key));
        if (!$item) {
            $exceptionClass = Config::getIveeClassName('KeyNotFoundInCacheException');
            throw new $exceptionClass("Key not found in Redis.");
        }
        //count hit
        $this->hits++;
        return unserialize($item);
    }

    /**
     * Removes item from Redis.
     *
     * @param string $key of object to be removed
     *
     * @return bool true on success
     */
    public function deleteItem($key)
    {
        return $this->redis->delete(md5($this->uniqId . '_' . $key));
    }

    /**
     * Removes multiple items from Redis.
     *
     * @param array $keys of items to be removed
     *
     * @return bool true on success, also if memcached has been disabled
     */
    public function deleteMulti(array $keys)
    {
        $keys2 = array();
        foreach ($keys as $key)
            $keys2[] = md5($this->uniqId . '_' . $key);
        return $this->redis->delete($keys2);
    }

    /**
     * Clears all stored items in current Redis DB.
     *
     * @return boolean true on success
     */
    public function flushCache()
    {
        return $this->redis->flushDB();
    }

    /**
     * Gets the number of hits the cache wrapper registered.
     *
     * @return int the number of hits
     */
    public function getHits()
    {
        return $this->hits; 
    }
}
