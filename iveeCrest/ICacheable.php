<?php
/**
 * ICacheable interface file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestInterfaces
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/ICacheable.php
 *
 */

namespace iveeCrest;

/**
 * Interface for cacheables. Defines the necessary methods for compatibility with InstancePool.
 *
 * @category IveeCrest
 * @package  IveeCrestInterfaces
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/ICacheable.php
 *
 */
interface ICacheable
{
    /**
     * Returns the key of the ICacheable object under which it is stored and retrieved from the cache
     *
     * @return string
     */
    public function getKey();

    /**
    * Gets the objects cache time to live
    *
    * @return int
    */
    public function getCacheTTL();
}
