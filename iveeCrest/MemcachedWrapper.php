<?php
/**
 * MemcachedWrapper class file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/MemcachedWrapper.php
 */

namespace iveeCrest;

/**
 * MemcachedWrapper provides caching functionality for iveeCrest based on php5-memcached.
 *
 * Pulling data from CREST is a relative expensive process thats slows down the client application and puts load onto
 * CCP's infrastructure. CCP thus asks developers to implement client side caching mechanisms, respecting the cache
 * times specified in the response header as much as possible.
 *
 * @category IveeCrest
 * @package  IveeCrestClasses
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/MemcachedWrapper.php
 */
class MemcachedWrapper implements ICache
{
    /**
     * @var \Memcached $memcached holds the Memcached connections.
     */
    protected $memcached;

    /**
     * @var int $hits stores the number of hits on memcached.
     */
    protected $hits = 0;

    /**
     * @var string $uniqId to be used to separate objects in addition to their key identifiers, for instance in a
     * multi-user scenario.
     */
    protected $uniqId;

    /**
     * Constructor
     *
     * @param string $uniqId to be used to separate objects in addition to their key identifiers, for instance in a
     * multi-user scenario.
     *
     * @return \iveeCrest\MemcachedWrapper
     */
    public function __construct($uniqId)
    {
        $this->memcached = new \Memcached;
        $this->memcached->addServer(Config::getCacheHost(), Config::getCachePort());
        $this->memcached->setOption(\Memcached::OPT_PREFIX_KEY, Config::getCachePrefix());
        $this->uniqId = $uniqId;
    }

    /**
     * Stores item in Memcached.
     *
     * @param ICacheable $item to be stored
     *
     * @return boolean true on success
     */
    public function setItem(ICacheable $item)
    {
        return $this->memcached->set(
            md5($this->uniqId . '_' . $item->getKey()),
            $item,
            $item->getCacheTTL()
        );
    }

    /**
     * Gets item from Memcached.
     *
     * @param string $key under which the item is stored
     *
     * @return mixed
     * @throws \iveeCrest\Exceptions\KeyNotFoundInCacheException if key is not found
     */
    public function getItem($key)
    {
        $item = $this->memcached->get(md5($this->uniqId . '_' . $key));
        if ($this->memcached->getResultCode() == \Memcached::RES_NOTFOUND) {
            $exceptionClass = Config::getIveeClassName('KeyNotFoundInCacheException');
            throw new $exceptionClass("Key not found in memcached.");
        }
        //count memcached hit
        $this->hits++;
        return $item;
    }

    /**
     * Removes item from Memcached.
     *
     * @param string $key of object to be removed
     *
     * @return bool true on success or if memcached has been disabled
     */
    public function deleteItem($key)
    {
        return $this->memcached->delete(md5($this->uniqId . '_' . $key));
    }

    /**
     * Removes multiple items from Memcached.
     * If using memcached, this method requires php5-memcached package version >=2.0!
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
        return $this->memcached->deleteMulti($keys2);
    }

    /**
     * Clears all stored items in memcached.
     *
     * @return boolean true on success, also if memcached has been disabled.
     */
    public function flushCache()
    {
        return $this->memcached->flush();
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
